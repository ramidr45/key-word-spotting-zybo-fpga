/*
 * resample.h -- reechantillonneur polyphase 48 kHz -> KWS_SAMPLE_RATE (flux continu)
 * Filtre passe-bas sinc fenetre (Blackman), coupure a 0.9 x Nyquist de sortie.
 */
#ifndef RESAMPLE_H
#define RESAMPLE_H

void resample_init(void);

/* pousse un echantillon d'entree (48 kHz) ; ecrit 0 ou 1 echantillon de sortie dans *out
 * et renvoie le nombre d'echantillons produits */
int resample_push(float x, float *out);

#endif
