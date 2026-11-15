/*
 * resample.c -- reechantillonnage rationnel IN_RATE -> OUT_RATE
 * Position de la sortie n en echantillons d'entree : t = n * IN / OUT
 *   t = ip + phase/DEN   avec DEN = OUT / pgcd(IN, OUT)
 * Table polyphase : DEN phases x NTAPS coefficients (16000 Hz -> 1 phase, 22050 -> 147).
 */
#include <math.h>
#include "kws_config.h"
#include "resample.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define HALF   24                    /* demi-longueur du noyau, en echantillons d'entree */
#define NTAPS  (2 * HALF)
#define HIST   128                   /* historique circulaire (puissance de 2 > NTAPS)   */

static int gcd_i(int a, int b) { while (b) { int t = a % b; a = b; b = t; } return a; }

#define G       (gcd_i(KWS_CODEC_RATE, KWS_SAMPLE_RATE))
static int NUM, DEN;                 /* t avance de NUM/DEN echantillons d'entree par sortie */
#define MAX_DEN 160
static float coef[MAX_DEN][NTAPS];
static float hist[HIST];
static unsigned wr = 0;              /* nb d'echantillons d'entree recus (modulo 2^32) */
static unsigned long long next_num;  /* position de la prochaine sortie x DEN          */
static unsigned long long in_count;

void resample_init(void)
{
    int p, j;
    double fc = 0.9 * (KWS_SAMPLE_RATE / 2.0) / KWS_CODEC_RATE;  /* coupure normalisee (cycles/ech.) */
    int g = G;
    NUM = KWS_CODEC_RATE / g;
    DEN = KWS_SAMPLE_RATE / g;
    if (DEN > MAX_DEN) DEN = MAX_DEN;    /* ne devrait pas arriver pour 16000/22050 */

    for (p = 0; p < DEN; p++) {
        double frac = (double)p / DEN, sum = 0.0;
        for (j = 0; j < NTAPS; j++) {
            /* echantillon d'entree d'indice (ip - HALF + 1 + j), distance a t : */
            double d = (double)(j - HALF + 1) - frac;
            double x = 2.0 * fc * d;
            double s = (fabs(x) < 1e-12) ? 1.0 : sin(M_PI * x) / (M_PI * x);
            double u = (d + HALF) / (2.0 * HALF);           /* 0..1 sur la fenetre */
            double w = (u <= 0.0 || u >= 1.0) ? 0.0
                       : 0.42 - 0.5 * cos(2 * M_PI * u) + 0.08 * cos(4 * M_PI * u);
            coef[p][j] = (float)(2.0 * fc * s * w);
            sum += coef[p][j];
        }
        for (j = 0; j < NTAPS; j++) coef[p][j] = (float)(coef[p][j] / sum);  /* gain DC = 1 */
    }
    for (j = 0; j < HIST; j++) hist[j] = 0.0f;
    wr = 0;
    in_count = 0;
    next_num = (unsigned long long)(HALF) * DEN;  /* premiere sortie quand le noyau est rempli */
}

int resample_push(float x, float *out)
{
#if KWS_SAMPLE_RATE == KWS_CODEC_RATE
    *out = x;                       /* meme frequence : pas de reechantillonnage */
    return 1;
#endif
    unsigned long long ip;
    int phase, j;
    float acc = 0.0f;

    hist[wr & (HIST - 1)] = x;
    wr++;
    in_count++;

    /* t = next_num / DEN ; on a besoin des echantillons jusqu'a ip + HALF */
    ip = next_num / DEN;
    if (ip + HALF >= in_count) return 0;   /* dernier echantillon requis : ip + HALF */

    phase = (int)(next_num % DEN);
    {
        /* indice du premier echantillon du noyau : ip - HALF + 1 */
        unsigned base = (unsigned)(ip - HALF + 1);
        const float *c = coef[phase];
        for (j = 0; j < NTAPS; j++)
            acc += c[j] * hist[(base + j) & (HIST - 1)];
    }
    next_num += NUM;
    *out = acc;
    return 1;
}
