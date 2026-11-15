#!/usr/bin/env python3
"""
features_ref.py -- extraction de features de REFERENCE (librosa), avec les parametres
lus directement dans sw/src/kws_config.h : une seule source de verite pour PC et carte.

  from features_ref import load_cfg, extract
  cfg = load_cfg()
  feat = extract(y, cfg)      # y : 1 s a cfg['sr'] Hz, float dans [-1, 1]
"""
import os
import re

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_CFG = os.path.join(HERE, "..", "sw", "src", "kws_config.h")


def load_cfg(path=DEFAULT_CFG):
    d = {}
    for line in open(path):
        m = re.match(r"\s*#define\s+(KWS_\w+)\s+(.*?)\s*(/\*.*)?$", line)
        if m and m.group(2):
            d[m.group(1)] = m.group(2)

    def num(name):
        v = d[name]
        for _ in range(4):                      # substitue les macros KWS_* imbriquees
            v = re.sub(r"\bKWS_\w+\b", lambda mm: "(" + d[mm.group(0)] + ")", v)
        v = re.sub(r"(\d)[fF]\b", r"\1", v)     # 2.0f -> 2.0
        return eval(v, {}, {})

    sr = int(num("KWS_SAMPLE_RATE"))
    return {
        "sr": sr,
        "n_fft": int(num("KWS_N_FFT")),
        "hop_length": int(num("KWS_HOP")),
        "n_mels": int(num("KWS_N_MELS")),
        "n_mfcc": int(num("KWS_N_MFCC")),
        "fmin": float(num("KWS_FMIN")),
        "fmax": float(num("KWS_FMAX")),
        "center": bool(int(num("KWS_CENTER"))),
        "pad_mode": "reflect" if int(num("KWS_PAD_REFLECT")) else "constant",
        "top_db": float(num("KWS_TOP_DB")),
    }


def extract(y, cfg, return_matrix=False):
    import librosa
    y = np.asarray(y, dtype=np.float32)
    n = cfg["sr"]
    if len(y) < n:
        y = np.pad(y, (0, n - len(y)))
    y = y[:n]
    S = librosa.feature.melspectrogram(
        y=y, sr=cfg["sr"], n_fft=cfg["n_fft"], hop_length=cfg["hop_length"],
        n_mels=cfg["n_mels"], fmin=cfg["fmin"], fmax=cfg["fmax"],
        center=cfg["center"], pad_mode=cfg["pad_mode"], power=2.0)
    S_db = librosa.power_to_db(S, ref=1.0, amin=1e-10,
                               top_db=cfg["top_db"] if cfg["top_db"] > 0 else None)
    M = librosa.feature.mfcc(S=S_db, n_mfcc=cfg["n_mfcc"])
    return (M.mean(axis=1), M) if return_matrix else M.mean(axis=1)


def predict_npz(feat, npz_path):
    """Inference numpy avec model_weights.npz (cree par export_weights.py --npz)."""
    d = np.load(npz_path, allow_pickle=False)
    h = (np.asarray(feat, np.float32) - d["mean"]) / d["std"]
    i = 0
    while f"W{i}" in d:
        h = h @ d[f"W{i}"] + d[f"b{i}"]
        act = str(d[f"act{i}"])
        if act == "relu":
            h = np.maximum(h, 0)
        elif act == "softmax":
            h = np.exp(h - h.max())
            h = h / h.sum()
        i += 1
    return h, [str(x) for x in d["labels"]]


if __name__ == "__main__":
    print(load_cfg())
