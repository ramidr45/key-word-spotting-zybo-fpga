/*
 * mlp.h -- inference d'un MLP dense (poids generes par tools/export_weights.py)
 */
#ifndef MLP_H
#define MLP_H

#include "model_weights.h"

/* x : MODEL_N_INPUT features BRUTES (la normalisation (x-mean)/std est faite ici)
 * probs : MODEL_N_CLASSES probabilites (softmax). Renvoie l'indice de la classe max. */
int mlp_predict(const float *x, float *probs);

#endif
