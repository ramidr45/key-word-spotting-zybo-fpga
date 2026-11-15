/*
 * mfcc.h -- MFCC compatibles librosa (voir kws_config.h)
 */
#ifndef MFCC_H
#define MFCC_H

#include "kws_config.h"

#define KWS_N_BINS    (KWS_N_FFT / 2 + 1)
#if KWS_CENTER
#define KWS_N_FRAMES  (1 + KWS_CLIP_SAMPLES / KWS_HOP)
#else
#define KWS_N_FRAMES  (1 + (KWS_CLIP_SAMPLES - KWS_N_FFT) / KWS_HOP)
#endif

/* a appeler une fois au demarrage (fenetre, banc de filtres mel, twiddles) */
void mfcc_init(void);

/*
 * Calcule la matrice MFCC [N_MFCC][N_FRAMES] (optionnelle, peut etre NULL)
 * et le vecteur moyen sur le temps mean_out[N_MFCC].
 * y : KWS_CLIP_SAMPLES echantillons float dans [-1, 1].
 */
void mfcc_compute(const float *y, float *mean_out, float (*mfcc_out)[KWS_N_FRAMES]);

#endif
