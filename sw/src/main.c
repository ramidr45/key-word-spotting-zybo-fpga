/*
 * main.c -- Keyword Spotting temps reel sur Zybo (Zynq-7010) (bare-metal, ARM Cortex-A9)
 *
 *  codec SSM2603 (48 kHz, 24 bits) -> FIFO PL -> reechantillonnage 16 kHz
 *  -> detection d'activite -> fenetre 1 s -> 13 MFCC moyennes -> MLP -> LEDs + UART
 *
 * UART 115200 8N1 (port USB PROG/UART).
 *
 * Switchs :  SW0 bouclage micro -> casque (materiel)
 *            SW1 detection automatique (sinon : uniquement BTN0)
 *            SW2 mode verbeux (affiche les 13 MFCC et toutes les probabilites)
 *            SW3 niveau : OFF = c0 remplace par sa moyenne d'entrainement (insensible au volume)
 *                         ON  = niveau brut
 * Boutons :  BTN0 enregistre 1 s maintenant puis classe
 *            BTN1 envoie la derniere fenetre classee sur l'UART (tools/uart_capture.py)
 *            BTN2 affiche l'etat (trames, niveau FIFO, bruit de fond, erreurs)
 *            BTN3 bascule l'entree micro (jack rose) <-> ligne (jack bleu) et reconfigure le codec
 * LEDs :     LD0 = yes, LD1 = no, LD2 = unknown,
 *            LD3 = ecoute / fenetre en cours
 */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "xil_printf.h"
#include "xtime_l.h"
#include "kws_hw.h"
#include "kws_config.h"
#include "resample.h"
#include "mfcc.h"
#include "mlp.h"

#define SR            KWS_SAMPLE_RATE
#define CLIP          KWS_CLIP_SAMPLES
#define RING          (2 * CLIP)                      /* 2 s d'historique */
#define BLOCK         (SR * KWS_BLOCK_MS / 1000)
#define PRE_ONSET     (SR * KWS_PRE_ONSET_MS / 1000)
#define POST_ONSET    (CLIP - PRE_ONSET)
#define REFRACTORY    (SR * KWS_REFRACTORY_MS / 1000)

static float ring[RING];
static unsigned long long n_out = 0;     /* nb total d'echantillons 16 kHz produits */
static float clip_buf[CLIP];
static float last_clip[CLIP];
static float last_feat[KWS_N_MFCC];
static float last_probs[MODEL_N_CLASSES];
static int   have_last = 0;

static float noise_rms = 0.01f;
static float blk_acc = 0.0f;
static int   blk_n = 0;
static float last_blk_rms = 0.0f;

static unsigned long long pending_at = 0;   /* n_out auquel lancer la classification (0 = aucune) */
static int pending_manual = 0;
static unsigned long long refractory_until = 0;
static unsigned overflow_count = 0;
static int32_t raw_peak = 0;          /* |echantillon brut 24 bits| max depuis le dernier BTN2 */

static uint32_t ctrl_base = CTRL_CAPTURE | CTRL_CH_LEFT;
static int line_mode = KWS_INPUT_LINE;
static uint32_t leds_state = LEDS_SW_CTRL;
static unsigned long long led_off_at = 0;

/* ---------------------------------------------------------------------------- */
static double now_s(void)
{
    XTime t;
    XTime_GetTime(&t);
    return (double)t / (double)COUNTS_PER_SECOND;
}

static void set_leds(uint32_t v)
{
    leds_state = LEDS_SW_CTRL | v;
    kws_wr(KWS_REG_LEDS, leds_state);
}

/* copie les CLIP derniers echantillons se terminant a l'index absolu end (exclu) */
static void extract_clip(unsigned long long end, float *dst)
{
    unsigned long long start = end - CLIP;
    int i;
    for (i = 0; i < CLIP; i++)
        dst[i] = ring[(start + i) % RING];
}

/* ---------------------------------------------------------------------------- */
/* choisit l'entree (micro / ligne), reconfigure le codec et attend la fin (max 2 s) */
static void set_input(int line)
{
    double t0;
    uint32_t st;
    line_mode = line;
    ctrl_base = CTRL_CAPTURE | (line ? (CTRL_LINE_IN | CTRL_CH_MIX) : CTRL_CH_LEFT);
    kws_wr(KWS_REG_CTRL, ctrl_base | CTRL_REINIT | CTRL_FIFO_CLEAR);
    t0 = now_s();
    do {
        st = kws_rd(KWS_REG_STATUS);
    } while (!(st & ST_INIT_DONE) && now_s() - t0 < 2.0);
    kws_wr(KWS_REG_CTRL, ctrl_base | CTRL_FIFO_CLEAR);
    printf("entree : %s   codec init=%d i2c_err=%d\r\n",
           line ? "LIGNE (jack bleu LINE IN)" : "MICRO (jack rose MIC IN)",
           !!(st & ST_INIT_DONE), !!(st & ST_I2C_ERR));
    noise_rms = 0.01f;
}

/* ---------------------------------------------------------------------------- */
static void classify(unsigned long long end, int verbose, int raw_level, const char *why)
{
    float feat[KWS_N_MFCC], probs[MODEL_N_CLASSES];
    float c0_raw, peak = 0.0f, rms = 0.0f, gain;
    double t0, t1, t2;
    int k, best;
    uint32_t led = 0;

    extract_clip(end, clip_buf);
    for (k = 0; k < CLIP; k++) {
        float a = fabsf(clip_buf[k]);
        if (a > peak) peak = a;
        rms += clip_buf[k] * clip_buf[k];
    }
    rms = sqrtf(rms / CLIP);

    t0 = now_s();
    mfcc_compute(clip_buf, feat, NULL);
    t1 = now_s();
    c0_raw = feat[0];
    /* gain equivalent (dB) qui ramenerait c0 a la moyenne d'entrainement : c0 = sqrt(n_mels).dB */
    gain = (model_norm_mean[0] - c0_raw) / sqrtf((float)KWS_N_MELS);
    if (!raw_level) feat[0] = model_norm_mean[0];
    best = mlp_predict(feat, probs);
    t2 = now_s();

    memcpy(last_clip, clip_buf, sizeof(last_clip));
    memcpy(last_feat, feat, sizeof(last_feat));
    memcpy(last_probs, probs, sizeof(last_probs));
    have_last = 1;

    if (probs[best] >= KWS_MIN_CONFIDENCE) {
        const char *lab = model_labels[best];
        printf("[%s] >>> %-8s p=%.2f", why, lab, probs[best]);
        if (strcmp(lab, "yes") == 0)      led = (1u << 0) | LEDS_G;
        else if (strcmp(lab, "no") == 0)  led = (1u << 1) | LEDS_R;
        else                              led = (1u << 2) | LEDS_B;
    } else {
        printf("[%s] >>> ?        (%s p=%.2f)", why, model_labels[best], probs[best]);
    }
    printf("   pic=%.3f rms=%.4f niveau=%+.0f dB  c0=%.1f (entrainement %.1f +/- %.1f)  mfcc %.1f ms, mlp %.2f ms\r\n",
           peak, rms, gain, c0_raw, model_norm_mean[0], model_norm_std[0],
           (t1 - t0) * 1e3, (t2 - t1) * 1e3);

    if (verbose) {
        printf("   probs :");
        for (k = 0; k < MODEL_N_CLASSES; k++) printf(" %s=%.3f", model_labels[k], probs[k]);
        printf("\r\n   mfcc  :");
        for (k = 0; k < KWS_N_MFCC; k++) printf(" %.3f", feat[k]);
        printf("\r\n");
    }

    set_leds(led);
    led_off_at = n_out + 2 * SR;           /* affichage pendant 2 s */
}

/* ---------------------------------------------------------------------------- */
static void dump_last_clip(void)
{
    int i, k;
    if (!have_last) { printf("rien a envoyer (aucune classification)\r\n"); return; }
    /* la capture continue dans la FIFO pendant l'envoi (~8 s) : on la coupe */
    kws_wr(KWS_REG_CTRL, ctrl_base & ~CTRL_CAPTURE);
    printf("DUMP_BEGIN sr=%d n=%d\r\n", SR, CLIP);
    printf("FEAT");
    for (k = 0; k < KWS_N_MFCC; k++) printf(" %.5f", last_feat[k]);
    printf("\r\nPROBS");
    for (k = 0; k < MODEL_N_CLASSES; k++) printf(" %.5f", last_probs[k]);
    printf("\r\n");
    for (i = 0; i < CLIP; i += 16) {
        for (k = 0; k < 16 && i + k < CLIP; k++) {
            float v = last_clip[i + k] * 32767.0f;
            int s = (int)lrintf(v > 32767.f ? 32767.f : (v < -32768.f ? -32768.f : v));
            printf(k ? ",%d" : "%d", s);
        }
        printf("\r\n");
    }
    printf("DUMP_END\r\n");
    kws_wr(KWS_REG_CTRL, ctrl_base | CTRL_FIFO_CLEAR);
}

static void print_status(void)
{
    uint32_t st = kws_rd(KWS_REG_STATUS);
    printf("etat : entree=%s init=%lu i2c_err=%lu mclk=%lu overflow=%lu fifo=%lu trames=%lu "
           "overflows_logiciel=%u bruit_rms=%.5f dernier_bloc=%.5f\r\n",
           line_mode ? "ligne" : "micro",
           (unsigned long)(st & ST_INIT_DONE ? 1 : 0), (unsigned long)(st & ST_I2C_ERR ? 1 : 0),
           (unsigned long)(st & ST_MCLK_LOCKED ? 1 : 0), (unsigned long)(st & ST_OVERFLOW ? 1 : 0),
           (unsigned long)ST_LEVEL(st), (unsigned long)kws_rd(KWS_REG_FRAMES),
           overflow_count, noise_rms, last_blk_rms);
    printf("       brut : dernier=0x%06lx  pic=%ld / 8388607 (%.1f dBFS)\r\n",
           (unsigned long)(kws_rd(KWS_REG_LAST) & 0xFFFFFFu), (long)raw_peak,
           raw_peak > 0 ? 20.0 * log10((double)raw_peak / 8388607.0) : -144.0);
    raw_peak = 0;
}

/* ---------------------------------------------------------------------------- */
/* nouvel echantillon a 16 kHz : anneau + detection d'activite */
static void on_sample(float s, int auto_mode)
{
    ring[n_out % RING] = s;
    n_out++;

    blk_acc += s * s;
    if (++blk_n == BLOCK) {
        float r = sqrtf(blk_acc / BLOCK);
        last_blk_rms = r;
        blk_acc = 0.0f;
        blk_n = 0;
        /* estimation du bruit de fond : suit vite vers le bas, lentement vers le haut */
        if (r < noise_rms) noise_rms = 0.7f * noise_rms + 0.3f * r;
        else               noise_rms = 0.995f * noise_rms + 0.005f * r;
        if (noise_rms < 1e-5f) noise_rms = 1e-5f;

        if (auto_mode && pending_at == 0 && n_out >= refractory_until && n_out > (unsigned long long)RING &&
            r > KWS_ONSET_FACTOR * noise_rms && r > KWS_ONSET_MIN_RMS) {
            /* debut de parole au debut de ce bloc */
            unsigned long long onset = n_out - BLOCK;
            pending_at = onset + POST_ONSET;
            pending_manual = 0;
            refractory_until = onset + REFRACTORY;
        }
    }
}

int main(void)
{
    uint32_t v, st, inputs, prev_btn = 0;
    unsigned long long t_wait;
    int i;

    printf("\r\n==== Keyword Spotting - Zybo ====\r\n");
    v = kws_rd(KWS_REG_VERSION);
    if (v != KWS_VERSION_ID) {
        printf("ERREUR : peripherique audio absent (VERSION=0x%08lx). Bitstream programme ?\r\n",
               (unsigned long)v);
        return 1;
    }
    printf("modele : %d -> %d classes (", MODEL_N_INPUT, MODEL_N_CLASSES);
    for (i = 0; i < MODEL_N_CLASSES; i++) printf(i ? ", %s" : "%s", model_labels[i]);
    printf(")\r\nfeatures : sr=%d n_fft=%d hop=%d n_mels=%d n_mfcc=%d trames=%d\r\n",
           KWS_SAMPLE_RATE, KWS_N_FFT, KWS_HOP, KWS_N_MELS, KWS_N_MFCC, KWS_N_FRAMES);

    mfcc_init();
    resample_init();

    /* attendre la configuration du codec (faite par le materiel) */
    printf("configuration du codec...");
    for (t_wait = 0; t_wait < 3000000ULL; t_wait++) {
        st = kws_rd(KWS_REG_STATUS);
        if (st & ST_INIT_DONE) break;
    }
    st = kws_rd(KWS_REG_STATUS);
    printf(" init=%d i2c_err=%d mclk=%d\r\n", !!(st & ST_INIT_DONE), !!(st & ST_I2C_ERR),
           !!(st & ST_MCLK_LOCKED));
    if (st & ST_I2C_ERR) printf("ATTENTION : NACK I2C -> verifier le codec (BTN3 pour reessayer)\r\n");

    set_input(line_mode);
    set_leds(0);
    printf("pret. SW1=ON : detection automatique ; BTN0 : capture 1 s ; BTN2 : etat ; BTN3 : micro/ligne\r\n");

    for (;;) {
        int auto_mode, verbose, raw_level;
        uint32_t btn, pressed, n;

        inputs = kws_rd(KWS_REG_INPUTS);
        auto_mode = (inputs >> 1) & 1;
        verbose   = (inputs >> 2) & 1;
        raw_level = (inputs >> 3) & 1;
        btn = (inputs >> 4) & 0xF;
        pressed = btn & ~prev_btn;
        prev_btn = btn;

        /* --- vidage de la FIFO materielle --- */
        st = kws_rd(KWS_REG_STATUS);
        if (st & ST_OVERFLOW) {
            overflow_count++;
            kws_wr(KWS_REG_CTRL, ctrl_base | CTRL_FIFO_CLEAR);
        }
        n = ST_LEVEL(st);
        while (n--) {
            int32_t raw = (int32_t)kws_rd(KWS_REG_DATA);
            int32_t a = raw < 0 ? -raw : raw;
            float y;
            if (a > raw_peak) raw_peak = a;
            float x = (float)raw * (KWS_INPUT_GAIN / 8388608.0f);   /* 24 bits -> [-1, 1] */
            if (resample_push(x, &y)) on_sample(y, auto_mode);
        }

        /* --- boutons --- */
        if (pressed & 0x1) {                       /* BTN0 : capture manuelle */
            pending_at = n_out + CLIP;
            pending_manual = 1;
            refractory_until = pending_at;
            printf("capture 1 s...\r\n");
        }
        if (pressed & 0x2) dump_last_clip();
        if (pressed & 0x4) print_status();
        if (pressed & 0x8) set_input(!line_mode);

        /* --- LED d'ecoute --- */
        if (pending_at != 0) {
            if (!(leds_state & (1u << 3))) set_leds((leds_state & 0x77u) | (1u << 3));
        }

        /* --- classification quand la fenetre est complete --- */
        if (pending_at != 0 && n_out >= pending_at) {
            classify(pending_at, verbose, raw_level, pending_manual ? "BTN" : "auto");
            pending_at = 0;
        }
        if (led_off_at != 0 && n_out >= led_off_at) {
            set_leds(0);
            led_off_at = 0;
        }
    }
    return 0;
}
