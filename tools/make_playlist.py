#!/usr/bin/env python3
"""
make_playlist.py -- fabrique une piste de test a jouer vers le jack bleu (LINE IN) de la Zybo.

A partir du dossier du dataset Google Speech Commands (ou d'un extrait), prend N clips
de 'yes', N de 'no' et N d'autres mots, les melange, les separe par 2 s de silence et
ecrit :
  playlist.wav         -> a jouer sur le PC (VLC, lecteur Windows...) vers LINE IN
  playlist_truth.txt   -> ordre attendu des mots (pour remplir la matrice de confusion)

Usage :
  python tools/make_playlist.py --data C:\\chemin\\speech_commands --n 10
Le dossier --data doit contenir les sous-dossiers yes/, no/, up/, stop/ ...
"""
import argparse
import glob
import os
import random

import numpy as np
from scipy.io import wavfile

OTHER_WORDS = ["up", "down", "left", "right", "on", "off", "stop", "go", "bed", "cat", "dog", "house"]


def load16k(path):
    sr, x = wavfile.read(path)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = x.astype(np.float32)
    if np.abs(x).max() > 1.5:
        x /= 32768.0
    if sr != 16000:
        from scipy.signal import resample_poly
        from math import gcd
        g = gcd(sr, 16000)
        x = resample_poly(x, 16000 // g, sr // g).astype(np.float32)
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True, help="dossier contenant yes/, no/, up/ ...")
    ap.add_argument("--n", type=int, default=10, help="clips par classe")
    ap.add_argument("--gap", type=float, default=2.0, help="silence entre mots (s)")
    ap.add_argument("--out", default="playlist.wav")
    ap.add_argument("--seed", type=int, default=0)
    a = ap.parse_args()
    rng = random.Random(a.seed)

    items = []
    for lab in ("yes", "no"):
        files = sorted(glob.glob(os.path.join(a.data, lab, "*.wav")))
        if not files:
            raise SystemExit(f"aucun fichier dans {os.path.join(a.data, lab)}")
        items += [(lab, f) for f in rng.sample(files, min(a.n, len(files)))]
    others = []
    for w in OTHER_WORDS:
        others += [(w, f) for f in glob.glob(os.path.join(a.data, w, "*.wav"))]
    if others:
        items += rng.sample(others, min(a.n, len(others)))
    rng.shuffle(items)

    gap = np.zeros(int(a.gap * 16000), np.float32)
    parts = [gap]
    truth = []
    for i, (lab, f) in enumerate(items):
        x = load16k(f)
        peak = np.abs(x).max()
        if peak > 0:
            x = x / peak * 0.7          # niveau homogene
        parts += [x, gap]
        truth.append(f"{i + 1:3d}  {('yes' if lab == 'yes' else 'no' if lab == 'no' else 'unknown'):8s} ({lab})  {os.path.basename(f)}")
    y = np.concatenate(parts)
    wavfile.write(a.out, 16000, (y * 32767).astype(np.int16))
    with open(os.path.splitext(a.out)[0] + "_truth.txt", "w") as fh:
        fh.write("\n".join(truth) + "\n")
    print(f"{a.out} : {len(items)} mots, {len(y) / 16000:.0f} s")
    print(f"ordre attendu : {os.path.splitext(a.out)[0]}_truth.txt")


if __name__ == "__main__":
    main()
