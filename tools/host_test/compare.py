#!/usr/bin/env python3
"""
compare.py -- verifie que le C du firmware (compile sur PC) donne les memes features
et les memes probabilites que librosa + numpy.

  cd tools/host_test && make && python3 compare.py [fichier.wav ...]

Sans argument : signaux de test synthetiques (voyelles, bruit, silence, sinus).
Avec des .wav (ex. clips Speech Commands) : compare sur de la vraie parole.
"""
import os
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from features_ref import load_cfg, extract, predict_npz  # noqa: E402

NPZ = os.path.join(HERE, "..", "..", "model", "model_weights.npz")
EXE = os.path.join(HERE, "kws_host")


def run_c(sig, from48=False):
    path = os.path.join(HERE, "tmp_in.f32")
    np.asarray(sig, np.float32).tofile(path)
    args = [EXE] + (["--from48k"] if from48 else []) + [path]
    out = subprocess.run(args, capture_output=True, text=True, cwd=HERE, check=True).stdout
    feat = probs = None
    for line in out.splitlines():
        if line.startswith("FEAT"):
            feat = np.array(line.split()[1:], float)
        elif line.startswith("PROBS"):
            probs = np.array(line.split()[1:], float)
    return feat, probs


def synth_signals(sr, rng):
    import scipy.signal as ss
    t = np.arange(sr) / sr
    sigs = {}
    sigs["sinus 440 Hz"] = 0.3 * np.sin(2 * np.pi * 440 * t)
    sigs["bruit blanc"] = 0.05 * rng.standard_normal(sr)
    sigs["quasi-silence"] = 1e-4 * rng.standard_normal(sr)
    for k, (f1, f2) in enumerate([(700, 1200), (300, 2300), (500, 900)]):
        x = np.zeros(sr)
        x[::int(sr / (110 + 30 * k))] = 1.0
        for f, bw in ((f1, 80), (f2, 100), (2600, 120)):
            r = np.exp(-np.pi * bw / sr)
            x = ss.lfilter([1 - r], [1, -2 * r * np.cos(2 * np.pi * f / sr), r * r], x)
        env = np.zeros(sr)
        a, b = int(0.3 * sr), int(0.75 * sr)
        env[a:b] = np.hanning(b - a)
        x = x * env
        sigs[f"voyelle {k}"] = 0.6 * x / np.abs(x).max() + 1e-4 * rng.standard_normal(sr)
    return sigs


def main():
    cfg = load_cfg()
    sr = cfg["sr"]
    rng = np.random.default_rng(1)
    if len(sys.argv) > 1:
        import librosa
        sigs = {os.path.basename(p): librosa.load(p, sr=sr)[0] for p in sys.argv[1:]}
    else:
        sigs = synth_signals(sr, rng)

    print(f"config : {cfg}")
    worst_f = worst_p = 0.0
    for name, y in sigs.items():
        y = np.asarray(y, np.float32)[:sr]
        y = np.pad(y, (0, sr - len(y)))
        f_ref = extract(y, cfg)
        f_c, p_c = run_c(y)
        p_ref, labels = predict_npz(f_ref, NPZ)
        df = np.max(np.abs(f_c - f_ref))
        dp = np.max(np.abs(p_c - p_ref))
        worst_f, worst_p = max(worst_f, df), max(worst_p, dp)
        print(f"{name:16s} |dMFCC|max={df:.2e}  |dP|max={dp:.2e}  "
              f"C:{labels[int(p_c.argmax())]:8s} ref:{labels[int(p_ref.argmax())]}")

    ok = worst_f < 1e-2 and worst_p < 1e-3
    print(f"\nC {sr} Hz vs librosa : ecart MFCC max = {worst_f:.2e}, ecart proba max = {worst_p:.2e}"
          f"  -> {'OK' if ok else 'ECHEC'}")

    # chaine complete carte : 48 kHz -> reechantillonnage C -> MFCC, vs librosa a 16 kHz
    import scipy.signal as ss
    y = sigs[list(sigs)[-1]].astype(np.float64)[:sr]
    y48 = ss.resample_poly(y, 3, 1) if sr == 16000 else ss.resample_poly(y, 48000, sr)
    f48, p48 = run_c(np.concatenate([y48, np.zeros(4800)]), from48=True)
    f_ref = extract(y.astype(np.float32), cfg)
    p_ref, labels = predict_npz(f_ref, NPZ)
    print(f"chaine 48k->{sr} (C) vs librosa {sr} : |dMFCC|max={np.max(np.abs(f48 - f_ref)):.3f} "
          f"(c0 {f48[0]:.1f} vs {f_ref[0]:.1f}), |dP|max={np.max(np.abs(p48 - p_ref)):.3f}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
