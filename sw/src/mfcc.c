/*
 * mfcc.c -- reproduction de librosa.feature.mfcc en C (float32)
 *   STFT (Hann periodique, centree) -> |X|^2 -> banc mel Slaney (norm='slaney')
 *   -> power_to_db(ref=1, amin, top_db sur toute la fenetre) -> DCT-II ortho
 * Aucune allocation dynamique : tout est statique.
 */
#include <math.h>
#include <string.h>
#include "mfcc.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define NFFT   KWS_N_FFT
#define NBINS  KWS_N_BINS
#define NMELS  KWS_N_MELS
#define NFR    KWS_N_FRAMES

/* --- tables ------------------------------------------------------------------- */
static float win[NFFT];
static float tw_re[NFFT / 2], tw_im[NFFT / 2];
static unsigned short bitrev[NFFT];
static float dct_tab[KWS_N_MFCC][NMELS];

/* banc mel creux : pour chaque filtre, plage de bins [lo, hi) et poids */
static int mel_lo[NMELS], mel_hi[NMELS];
static float mel_w[NMELS][NBINS];      /* seule la plage [lo,hi) est utilisee */

/* tampons de travail */
static float fr_re[NFFT], fr_im[NFFT];
static float melspec[NFR][NMELS];       /* en dB apres conversion */
static float padded[KWS_CLIP_SAMPLES + NFFT];

/* --- echelle mel Slaney (librosa htk=False) ------------------------------------ */
static double hz_to_mel(double f)
{
    const double f_sp = 200.0 / 3.0, min_log_hz = 1000.0;
    const double min_log_mel = min_log_hz / f_sp, logstep = log(6.4) / 27.0;
    if (f >= min_log_hz) return min_log_mel + log(f / min_log_hz) / logstep;
    return f / f_sp;
}
static double mel_to_hz(double m)
{
    const double f_sp = 200.0 / 3.0, min_log_hz = 1000.0;
    const double min_log_mel = min_log_hz / f_sp, logstep = log(6.4) / 27.0;
    if (m >= min_log_mel) return min_log_hz * exp(logstep * (m - min_log_mel));
    return f_sp * m;
}

void mfcc_init(void)
{
    int i, k, m;
    int bits = 0;

    /* fenetre de Hann periodique (scipy get_window('hann', N, fftbins=True)) */
    for (i = 0; i < NFFT; i++)
        win[i] = (float)(0.5 - 0.5 * cos(2.0 * M_PI * i / NFFT));

    /* FFT radix-2 */
    while ((1 << bits) < NFFT) bits++;
    for (i = 0; i < NFFT; i++) {
        unsigned r = 0, x = (unsigned)i;
        for (k = 0; k < bits; k++) { r = (r << 1) | (x & 1u); x >>= 1; }
        bitrev[i] = (unsigned short)r;
    }
    for (i = 0; i < NFFT / 2; i++) {
        tw_re[i] = (float)cos(-2.0 * M_PI * i / NFFT);
        tw_im[i] = (float)sin(-2.0 * M_PI * i / NFFT);
    }

    /* banc de filtres mel (librosa.filters.mel, norm='slaney') -- calcul en double */
    {
        static double mel_f[NMELS + 2];
        double mmin = hz_to_mel(KWS_FMIN), mmax = hz_to_mel(KWS_FMAX);
        for (m = 0; m < NMELS + 2; m++)
            mel_f[m] = mel_to_hz(mmin + (mmax - mmin) * m / (NMELS + 1));
        for (m = 0; m < NMELS; m++) {
            double fd0 = mel_f[m + 1] - mel_f[m];
            double fd1 = mel_f[m + 2] - mel_f[m + 1];
            double enorm = 2.0 / (mel_f[m + 2] - mel_f[m]);
            int lo = NBINS, hi = 0;
            for (k = 0; k < NBINS; k++) {
                double f = (double)KWS_SAMPLE_RATE / 2.0 * k / (NBINS - 1);
                double lower = (f - mel_f[m]) / fd0;      /* -ramps[m] / fdiff[m]   */
                double upper = (mel_f[m + 2] - f) / fd1;  /* ramps[m+2] / fdiff[m+1] */
                double w = lower < upper ? lower : upper;
                if (w < 0.0) w = 0.0;
                mel_w[m][k] = (float)(w * enorm);
                if (w > 0.0) { if (k < lo) lo = k; if (k + 1 > hi) hi = k + 1; }
            }
            if (lo > hi) { lo = 0; hi = 0; }              /* filtre vide (rare) */
            mel_lo[m] = lo; mel_hi[m] = hi;
        }
    }

    /* DCT-II orthonormee (scipy.fft.dct(type=2, norm='ortho')) */
    for (k = 0; k < KWS_N_MFCC; k++) {
        double s = (k == 0) ? sqrt(1.0 / NMELS) : sqrt(2.0 / NMELS);
        for (m = 0; m < NMELS; m++)
            dct_tab[k][m] = (float)(s * cos(M_PI * k * (2 * m + 1) / (2.0 * NMELS)));
    }
}

static void fft_inplace(float *re, float *im)
{
    int i, len, j;
    for (i = 0; i < NFFT; i++) {
        int r = bitrev[i];
        if (r > i) {
            float t = re[i]; re[i] = re[r]; re[r] = t;
            t = im[i]; im[i] = im[r]; im[r] = t;
        }
    }
    for (len = 2; len <= NFFT; len <<= 1) {
        int half = len >> 1, step = NFFT / len;
        for (i = 0; i < NFFT; i += len) {
            for (j = 0; j < half; j++) {
                float wr = tw_re[j * step], wi = tw_im[j * step];
                float xr = re[i + j + half], xi = im[i + j + half];
                float tr = xr * wr - xi * wi;
                float ti = xr * wi + xi * wr;
                re[i + j + half] = re[i + j] - tr;
                im[i + j + half] = im[i + j] - ti;
                re[i + j] += tr;
                im[i + j] += ti;
            }
        }
    }
}

void mfcc_compute(const float *y, float *mean_out, float (*mfcc_out)[KWS_N_FRAMES])
{
    int t, k, m, i;
    const float *src;
    float maxdb = -1e30f;
    float acc[KWS_N_MFCC];

#if KWS_CENTER
    {
        const int P = NFFT / 2, N = KWS_CLIP_SAMPLES;
        memcpy(&padded[P], y, sizeof(float) * N);
        for (i = 0; i < P; i++) {
#if KWS_PAD_REFLECT
            padded[P - 1 - i] = y[i + 1];
            padded[P + N + i] = y[N - 2 - i];
#else
            padded[P - 1 - i] = 0.0f;
            padded[P + N + i] = 0.0f;
#endif
        }
        src = padded;
    }
#else
    src = y;
#endif

    for (t = 0; t < NFR; t++) {
        const float *x = src + t * KWS_HOP;
        for (i = 0; i < NFFT; i++) { fr_re[i] = x[i] * win[i]; fr_im[i] = 0.0f; }
        fft_inplace(fr_re, fr_im);
        /* puissance (on reutilise fr_re pour |X|^2) */
        for (k = 0; k < NBINS; k++)
            fr_re[k] = fr_re[k] * fr_re[k] + fr_im[k] * fr_im[k];
        for (m = 0; m < NMELS; m++) {
            float s = 0.0f, db;
            for (k = mel_lo[m]; k < mel_hi[m]; k++) s += mel_w[m][k] * fr_re[k];
            db = 10.0f * log10f(s > KWS_AMIN ? s : KWS_AMIN);
            melspec[t][m] = db;
            if (db > maxdb) maxdb = db;
        }
    }

    if (KWS_TOP_DB > 0.0f) {
        float floor_db = maxdb - KWS_TOP_DB;
        for (t = 0; t < NFR; t++)
            for (m = 0; m < NMELS; m++)
                if (melspec[t][m] < floor_db) melspec[t][m] = floor_db;
    }

    for (k = 0; k < KWS_N_MFCC; k++) acc[k] = 0.0f;
    for (t = 0; t < NFR; t++) {
        for (k = 0; k < KWS_N_MFCC; k++) {
            float s = 0.0f;
            for (m = 0; m < NMELS; m++) s += dct_tab[k][m] * melspec[t][m];
            if (mfcc_out) mfcc_out[k][t] = s;
            acc[k] += s;
        }
    }
    for (k = 0; k < KWS_N_MFCC; k++) mean_out[k] = acc[k] / (float)NFR;
}
