/*
 * host_main.c -- execute la chaine du firmware (memes fichiers C) sur PC.
 *
 *   ./kws_host clip16k.f32            -> MFCC moyens + probabilites (fenetre 1 s a 16 kHz)
 *   ./kws_host --from48k audio48k.f32 -> reechantillonne d'abord 48 kHz -> 16 kHz comme
 *                                         sur la carte, puis MFCC + MLP
 * Fichiers .f32 : float32 little-endian bruts dans [-1, 1].
 * Sortie : une ligne "FEAT ..." et une ligne "PROBS ..." (lue par compare.py)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "kws_config.h"
#include "mfcc.h"
#include "mlp.h"
#include "resample.h"

static float clip[KWS_CLIP_SAMPLES];

int main(int argc, char **argv)
{
    int from48 = 0, i, n = 0, best;
    const char *path;
    FILE *f;
    float feat[KWS_N_MFCC], probs[MODEL_N_CLASSES];

    if (argc < 2) { fprintf(stderr, "usage: %s [--from48k] fichier.f32\n", argv[0]); return 1; }
    if (strcmp(argv[1], "--from48k") == 0) { from48 = 1; path = argv[2]; } else path = argv[1];
    f = fopen(path, "rb");
    if (!f) { perror(path); return 1; }

    mfcc_init();
    resample_init();
    memset(clip, 0, sizeof(clip));

    if (from48) {
        float x, y;
        while (fread(&x, sizeof(float), 1, f) == 1)
            if (resample_push(x, &y) && n < KWS_CLIP_SAMPLES) clip[n++] = y;
    } else {
        n = (int)fread(clip, sizeof(float), KWS_CLIP_SAMPLES, f);
    }
    fclose(f);
    fprintf(stderr, "%d echantillons a %d Hz\n", n, KWS_SAMPLE_RATE);

    if (from48) {
        FILE *o = fopen("resampled16k.f32", "wb");
        fwrite(clip, sizeof(float), KWS_CLIP_SAMPLES, o);
        fclose(o);
    }

    mfcc_compute(clip, feat, NULL);
    best = mlp_predict(feat, probs);

    printf("FEAT");
    for (i = 0; i < KWS_N_MFCC; i++) printf(" %.6f", feat[i]);
    printf("\nPROBS");
    for (i = 0; i < MODEL_N_CLASSES; i++) printf(" %.6f", probs[i]);
    printf("\nCLASS %d %s\n", best, model_labels[best]);
    return 0;
}
