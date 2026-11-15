/*
 * mlp.c -- MLP dense generique : couches decrites dans model_weights.h
 *   W stocke en [sortie][entree] (transpose du kernel Keras), activations relu/softmax/linear
 */
#include <math.h>
#include "mlp.h"

#define ACT_LINEAR  0
#define ACT_RELU    1
#define ACT_SOFTMAX 2

static void dense(const float *in, float *out, const float *W, const float *b,
                  int n_in, int n_out, int act)
{
    int o, i;
    for (o = 0; o < n_out; o++) {
        const float *w = W + o * n_in;
        float s = b[o];
        for (i = 0; i < n_in; i++) s += w[i] * in[i];
        out[o] = s;
    }
    if (act == ACT_RELU) {
        for (o = 0; o < n_out; o++) if (out[o] < 0.0f) out[o] = 0.0f;
    } else if (act == ACT_SOFTMAX) {
        float mx = out[0], sum = 0.0f;
        for (o = 1; o < n_out; o++) if (out[o] > mx) mx = out[o];
        for (o = 0; o < n_out; o++) { out[o] = expf(out[o] - mx); sum += out[o]; }
        for (o = 0; o < n_out; o++) out[o] /= sum;
    }
}

int mlp_predict(const float *x, float *probs)
{
    static float bufA[MODEL_MAX_WIDTH], bufB[MODEL_MAX_WIDTH];
    float *cur = bufA, *nxt = bufB, *t;
    int i, l, best = 0;

    for (i = 0; i < MODEL_N_INPUT; i++)
        cur[i] = (x[i] - model_norm_mean[i]) / model_norm_std[i];

    for (l = 0; l < MODEL_N_LAYERS; l++) {
        dense(cur, nxt, model_layers[l].W, model_layers[l].b,
              model_layers[l].n_in, model_layers[l].n_out, model_layers[l].act);
        t = cur; cur = nxt; nxt = t;
    }
    for (i = 0; i < MODEL_N_CLASSES; i++) {
        probs[i] = cur[i];
        if (cur[i] > cur[best]) best = i;
    }
    return best;
}
