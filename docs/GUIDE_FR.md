# Keyword Spotting temps réel — Zybo (1re génération, Zynq-7010, avec port VGA)

Détection de mots-clés **yes / no / unknown** à partir du micro de la Zybo.

```
micro (jack rose) → SSM2603 ──I2S 48 kHz/24 bits──► PL (VHDL)                    PS (ARM Cortex-A9, C)
                     ▲  ▲                           ├ i2s_rx (suréchantillonné)  ├ rééchantillonnage 48k → 16k
          MCLK 12.288│  │I2C                        ├ FIFO 8192×32 ──AXI-Lite──► ├ détection d'activité
          (clk_wiz)  │  └── ssm2603_ctrl/i2c_master ├ LEDs / switchs / boutons   ├ 13 MFCC (identiques librosa)
                                                    └ bouclage micro → casque    └ MLP 13-128-64-32-3 → LEDs + UART
```

Le modèle est **le tien** (`model/best_model.keras`, normalisation `norm_mean/std.npy`),
converti dans `sw/src/model_weights.h`.

---

## 1. Prérequis

| Outil | Version |
|---|---|
| Vivado + Xilinx SDK | 2018.2 (les scripts gèrent aussi 2019.2+ pour l'export `.xsa`, mais l'app est prévue pour SDK) |
| Fichiers de carte Digilent | dossier **`zybo`** (et non `zybo-z7-10`) de [github.com/Digilent/vivado-boards](https://github.com/Digilent/vivado-boards) (`new/board_files`) copié dans `C:\Xilinx\Vivado\2018.2\data\boards\board_files\` |
| Terminal série | PuTTY / Tera Term, **115200 8N1** |
| Python (outils PC, optionnel) | `pip install -r tools/requirements.txt` |

Matériel : Zybo, câble USB sur **PROG/UART (J12)**, cavalier **JP5 sur JTAG**,
micro électret / casque-micro sur le jack **MIC IN (rose)**, casque sur **HPH OUT (noir)** (optionnel).

---

## 2. Construire (une commande)

Windows (adapter `XILINX`/`VER` en haut du fichier si besoin) :
```
build_all.bat run
```
Linux : `XILINX=/opt/Xilinx VER=2018.2 ./build_all.sh run`

Étapes manuelles équivalentes :
```
vivado -mode batch -source hw/scripts/build_hw.tcl     → hw/build/out/top.bit + top.hdf (10-20 min)
xsct sw/scripts/create_sdk.tcl                          → sw/workspace/kws_app/Release/kws_app.elf
xsct sw/scripts/run_on_board.tcl                        → programme FPGA + lance l'appli (JTAG)
```
Option carte SD : `xsct sw/scripts/make_bootbin.tcl` → `sw/boot/BOOT.BIN` (JP5 sur SD).

> Ouvre le terminal série **avant** `run_on_board.tcl` pour voir le message de démarrage.

---

## 3. Procédure de test sur carte (dans l'ordre)

### Test 1 — matériel seul (sans logiciel)
Juste après la programmation du FPGA, les LEDs sont pilotées par le matériel :

| LED | Attendu | Si ce n'est pas le cas |
|---|---|---|
| LD0 | clignote (~0,75 Hz) | horloge PL absente → le PS n'est pas initialisé (ps7_init) |
| LD1 | allumée = codec configuré | MCLK non verrouillée ou séquenceur bloqué |
| LD2 | **éteinte** (allumée = NACK I2C) | câblage/adresse I2C, BTN3 pour réessayer |
| LD3 | s'allume quand tu parles / tapotes le micro | pas d'I2S : vérifier MCLK, jack rose |

**SW0 = ON** : bouclage micro → casque (jack noir). Tu dois t'entendre : ça valide toute la chaîne analogique + I2S sans aucun code.

### Test 2 — logiciel
Dans le terminal :
```
==== Keyword Spotting - Zybo ====
modele : 13 -> 3 classes (yes, no, unknown)
features : sr=16000 n_fft=2048 hop=512 n_mels=128 n_mfcc=13 trames=32
configuration du codec... init=1 i2c_err=0 mclk=1
pret. ...
```
- **BTN2** : affiche l'état (trames reçues qui augmentent, FIFO, bruit de fond).
- **BTN0** puis dire « yes » : classification de la seconde suivante.
- **SW1 = ON** : détection automatique (début de parole détecté → fenêtre de 1 s → résultat).

Résultat : `[auto] >>> yes      p=0.91 ...`
LEDs : **LD0 = yes**, **LD1 = no**, **LD2 = unknown**, LD3 = écoute en cours.
Sous 0,60 de confiance → `?` et aucune LED.

### Test 3 — vérifier la cohérence carte / Python
```
python tools/uart_capture.py --port COM5
```
Appuie sur **BTN1** : la dernière fenêtre classée est envoyée (~8 s), sauvée en
`captures/clip_000.wav`, et ses MFCC sont recalculés avec librosa pour comparaison
(écart attendu < 0,01 sauf c0 si SW3 = OFF, voir ci-dessous).
Ces `.wav` servent aussi à **réentraîner le modèle avec ton micro**.

### Switchs et boutons

| | Rôle |
|---|---|
| SW0 | bouclage micro → casque (matériel) |
| SW1 | détection automatique ON/OFF |
| SW2 | mode verbeux (13 MFCC + toutes les probabilités) |
| SW3 | OFF : c0 recalé sur la moyenne d'entraînement (insensible au gain du micro, **recommandé**) · ON : niveau brut |
| BTN0 | capture manuelle 1 s |
| BTN1 | envoi de la dernière fenêtre sur l'UART |
| BTN2 | état |
| BTN3 | bascule entrée micro (jack rose) ↔ ligne (jack bleu, par défaut) |

---

## 4. Paramètres MFCC (identiques au notebook Kaggle)

```python
y, _ = librosa.load(f, sr=48000)            # 1 s, pad/tronque a 48000
mfcc = librosa.feature.mfcc(y=y, sr=48000, n_mfcc=13, n_fft=512, hop_length=512,
                            n_mels=26, window="hann")
feat = mfcc.mean(axis=1)                    # 13 valeurs
```
Le codec tourne à 48 kHz : aucun rééchantillonnage sur la carte. Les paramètres sont dans
`sw/src/kws_config.h` (lus aussi par les outils Python). Le C a été vérifié contre librosa :
écart MFCC ≤ 2·10⁻⁴, écart de probabilité ≤ 10⁻⁶.

**Volume :** seul c0 (énergie) dépend du niveau d'entrée. Avec SW3 = OFF, c0 est remplacé par sa
moyenne d'entraînement, ce qui équivaut à une normalisation exacte du gain.

## 5. Ce qui a été vérifié (sans carte)

| Vérification | Résultat |
|---|---|
| Simulation GHDL du périphérique (`hw/sim/run_sim.sh`) | **PASSED** : 10 écritures I2C exactes + ACK, échantillons I2S 24 bits bit-exacts via la FIFO/AXI, canal droit, overflow, clear, LEDs |
| C du firmware compilé sur PC vs librosa (`tools/host_test`) | écart MFCC ≤ 3·10⁻⁴, écart probabilités ≤ 10⁻⁶ |
| Chaîne carte complète 48 kHz → rééchantillonnage C → MFCC → MLP | écart probabilités ≤ 0,002 (0,006 à 22 050 Hz) |
| `export_weights.py` sur ton modèle | 72,95 % sur `X_features.npy` (identique à l'entraînement) |
| `main.c` | compile sans avertissement (`-Wall -Wextra`) |

**Non vérifié ici** (pas de Vivado dans mon environnement) : l'exécution des scripts
Tcl Vivado/SDK et le timing. Si un script s'arrête, envoie-moi le log
(`hw/build_hw.log` ou la sortie de xsct).

---

## 6. Arborescence

```
hw/rtl/          i2c_master, ssm2603_ctrl, i2s_rx, audio_fifo, kws_audio_axi, top
hw/constraints/  zybo.xdc
hw/scripts/      build_hw.tcl, bd_system.tcl
hw/sim/          tb_kws_audio.vhd, run_sim.sh (GHDL)
sw/src/          main.c, mfcc.c, mlp.c, resample.c, kws_config.h, kws_hw.h, model_weights.h
sw/scripts/      create_sdk.tcl, run_on_board.tcl, make_bootbin.tcl
tools/           export_weights.py, features_ref.py, uart_capture.py, host_test/
model/           best_model.keras, norm_mean/std.npy, model_weights.npz
```

Changer de modèle :
```
python tools/export_weights.py --model model/best_model.keras --mean model/norm_mean.npy \
       --std model/norm_std.npy --labels yes,no,unknown --out sw/src/model_weights.h \
       --npz model/model_weights.npz
```

## 7. Registres (base 0x43C0_0000)

| Off. | Nom | Description |
|---|---|---|
| 0x00 | CTRL | b0 capture, b1 vider FIFO, b2 reconfig codec, b3 bouclage, b5:4 canal (G/D/moyenne) |
| 0x04 | STATUS | b0 init, b1 err I2C, b2 overflow, b3 vide, b4 pleine, b5 MCLK OK, b29:16 niveau |
| 0x08 | DATA | lecture = dépile un échantillon 24 bits signé |
| 0x0C | FRAMES | trames I2S reçues |
| 0x10 | LEDS | b3:0 LEDs, b31 contrôle logiciel (b6:4 RGB inutilisés sur cette carte) |
| 0x14 | VERSION | 0x4B575331 « KWS1 » |
| 0x18 | LAST | dernier échantillon gauche |
| 0x1C | INPUTS | b3:0 switchs, b7:4 boutons |
| 0x20 | THRESH | seuil LD3 |
| 0x24 | LEVEL | niveau FIFO |

## 8. Dépannage rapide

| Symptôme | Piste |
|---|---|
| `build_hw.tcl` : fichiers de carte introuvables | installer `zybo-z7-10` (§1) |
| `VERSION=0x00000000` au démarrage | bitstream non chargé ou adresse différente : voir le message `INFO: segment` dans le log Vivado |
| LD2 allumée | NACK I2C : BTN3 ; vérifier que la carte est bien une Z7 (codec à 0x1A) |
| LD1 allumée, LD3 ne réagit pas | micro dans le mauvais jack, ou micro sans polarisation ; tester avec SW0 + casque |
| `overflow` dans BTN2 | normal juste après un envoi BTN1 ; sinon impressions trop longues |
| toujours `unknown` | regarder c0 (SW2) ; tester SW3 ; confirmer les paramètres MFCC (§4) |

## 9. Entrée ligne (sans micro)

Par défaut, l'entrée est **LINE IN (jack bleu)** : relier la sortie casque d'un PC ou d'un
téléphone avec un câble jack-jack 3,5 mm, puis jouer des enregistrements de « yes » / « no ».
BTN3 bascule vers le micro (jack rose, micro 3 contacts ; un kit de téléphone 4 contacts ne
fonctionne pas sans adaptateur). Valeur au démarrage : `KWS_INPUT_LINE` dans `sw/src/kws_config.h`.
