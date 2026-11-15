#!/usr/bin/env python3
"""
uart_capture.py -- console serie + recuperation des fenetres envoyees par la carte (BTN1).

  pip install pyserial numpy scipy librosa
  python tools/uart_capture.py --port COM5          (Windows)
  python tools/uart_capture.py --port /dev/ttyUSB1  (Linux)

Affiche tout ce que la carte envoie. A chaque appui sur BTN1, la derniere fenetre de 1 s
classee est recue, sauvegardee en captures/clip_XXX.wav, puis :
  * les MFCC sont recalcules avec librosa (features_ref.py) et compares a ceux de la carte,
  * le modele (model/model_weights.npz) est execute en numpy pour comparer les probabilites.
Les .wav sauvegardes peuvent servir a reentrainer le modele avec VOTRE micro.
"""
import argparse
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def save_wav(path, sr, x_int16):
    from scipy.io import wavfile
    wavfile.write(path, sr, x_int16.astype(np.int16))


def analyse(clip, sr, feat_board, probs_board, npz):
    try:
        from features_ref import load_cfg, extract, predict_npz
    except Exception as e:  # librosa absent
        print("  (analyse impossible :", e, ")")
        return
    cfg = load_cfg()
    y = clip.astype(np.float32) / 32767.0
    f_ref = extract(y, cfg)
    print("  MFCC carte  :", np.array2string(feat_board, precision=2, max_line_width=200))
    print("  MFCC librosa:", np.array2string(f_ref, precision=2, max_line_width=200))
    d = np.abs(f_ref - feat_board)
    print(f"  ecart max = {d.max():.3f} (c0 ecart {d[0]:.2f} : normal si SW3=OFF, c0 recale)")
    if os.path.exists(npz):
        p, labels = predict_npz(f_ref, npz)
        print("  probas carte  :", " ".join(f"{l}={v:.3f}" for l, v in zip(labels, probs_board)))
        print("  probas python :", " ".join(f"{l}={v:.3f}" for l, v in zip(labels, p)),
              "(niveau brut)")


def main():
    import serial
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--out", default=os.path.join(HERE, "..", "captures"))
    ap.add_argument("--npz", default=os.path.join(HERE, "..", "model", "model_weights.npz"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    ser = serial.Serial(a.port, a.baud, timeout=0.5)
    print(f"ouvert {a.port} @ {a.baud}. Ctrl+C pour quitter.")
    in_dump = False
    rows, feat, probs, sr = [], None, None, 16000
    k = len([f for f in os.listdir(a.out) if f.endswith(".wav")])
    while True:
        try:
            raw = ser.readline()
        except KeyboardInterrupt:
            break
        if not raw:
            continue
        line = raw.decode(errors="replace").strip()
        if line.startswith("DUMP_BEGIN"):
            in_dump, rows = True, []
            for tok in line.split()[1:]:
                if tok.startswith("sr="):
                    sr = int(tok[3:])
            print("reception d'une fenetre...", end="", flush=True)
            t0 = time.time()
            continue
        if in_dump:
            if line.startswith("FEAT"):
                feat = np.array(line.split()[1:], float)
            elif line.startswith("PROBS"):
                probs = np.array(line.split()[1:], float)
            elif line.startswith("DUMP_END"):
                in_dump = False
                clip = np.array([int(v) for r in rows for v in r.split(",") if v], np.int32)
                path = os.path.join(a.out, f"clip_{k:03d}.wav")
                save_wav(path, sr, np.clip(clip, -32768, 32767))
                k += 1
                print(f" {len(clip)} echantillons en {time.time() - t0:.1f} s -> {path}")
                if feat is not None and probs is not None:
                    analyse(clip, sr, feat, probs, a.npz)
            elif line:
                rows.append(line)
            continue
        print(line)


if __name__ == "__main__":
    main()
