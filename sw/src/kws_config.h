/*
 * kws_config.h -- parametres de l'extraction de features (DOIVENT correspondre
 * exactement a ceux utilises pour l'entrainement en Python).
 *
 * Valeurs = notebook Kaggle (v2, 13 features) :
 *   y, _ = librosa.load(f, sr=48000) ; pad/tronque a 48000
 *   librosa.feature.mfcc(y=y, sr=48000, n_mfcc=13, n_fft=512, hop_length=512, n_mels=26,
 *                        window='hann')   (center=True, pad 'constant', top_db=80)
 *   puis np.mean(mfcc, axis=1)  -> vecteur de 13 valeurs.
 *
 * Si votre notebook utilise d'autres valeurs (ex. librosa.load sans sr -> 22050 Hz,
 * ou n_fft=512/hop=160/n_mels=40), modifiez-les ici ET dans tools/features.json.
 */
#ifndef KWS_CONFIG_H
#define KWS_CONFIG_H

/* --- audio ------------------------------------------------------------------ */
#define KWS_CODEC_RATE     48000      /* frequence du codec (fixee par le materiel)   */
#define KWS_SAMPLE_RATE    48000      /* frequence vue par le modele (= codec : pas de reechantillonnage) */
#define KWS_CLIP_SAMPLES   KWS_SAMPLE_RATE   /* fenetre de 1 s                         */

/* --- MFCC (librosa) ----------------------------------------------------------- */
#define KWS_N_FFT          512        /* puissance de 2 obligatoire                   */
#define KWS_HOP            512
#define KWS_N_MELS         26 
#define KWS_N_MFCC         13
#define KWS_FMIN           0.0f
#define KWS_FMAX           (KWS_SAMPLE_RATE / 2.0f)
#define KWS_CENTER         1          /* center=True                                  */
#define KWS_PAD_REFLECT    0          /* 0 : 'constant' (librosa >= 0.10), 1 : 'reflect' */
#define KWS_TOP_DB         80.0f      /* <= 0 pour desactiver                         */
#define KWS_AMIN           1e-10f

/* --- detection ----------------------------------------------------------------- */
#define KWS_BLOCK_MS       20         /* bloc d'energie pour la detection d'activite   */
#define KWS_ONSET_FACTOR   4.0f       /* debut de parole si RMS bloc > facteur x bruit */
#define KWS_ONSET_MIN_RMS  0.002f     /* RMS minimum absolu (pleine echelle = 1.0)     */
#define KWS_PRE_ONSET_MS   350        /* la fenetre de 1 s commence 350 ms avant le debut */
#define KWS_REFRACTORY_MS  1200       /* pas de nouvelle detection pendant ce temps    */
#define KWS_MIN_CONFIDENCE 0.60f      /* sous ce seuil -> resultat affiche "?"          */

/* entree audio au demarrage : 1 = LINE IN (jack bleu, cable jack-jack depuis PC/telephone),
 * 0 = MIC IN (jack rose, micro 3 contacts). BTN3 bascule pendant l'execution. */
#define KWS_INPUT_LINE     1

/* compensation du volume : SW3=OFF -> c0 (energie) remplace par sa moyenne d'entrainement.
 * Les coefficients c1..c12 ne dependent pas du volume : c'est equivalent a une normalisation
 * exacte du gain. SW3=ON -> niveau brut. */

/* gain numerique applique aux echantillons du codec (24 bits -> [-1,1]) */
#define KWS_INPUT_GAIN     1.0f

#endif
