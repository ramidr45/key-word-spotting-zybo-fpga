#!/usr/bin/env python3
"""
export_weights.py -- convertit un modele Keras (.keras Keras 3 ou .h5) + normalisation
en sw/src/model_weights.h pour le firmware Zybo.

Aucune dependance a TensorFlow : lecture directe avec h5py + numpy.

Usage :
  python tools/export_weights.py --model best_model.keras \
      --mean norm_mean.npy --std norm_std.npy \
      --labels yes,no,unknown --out sw/src/model_weights.h

Verification optionnelle (precision sur vos features) :
  ... --check-x X_features.npy --check-y y_labels.npy
"""
import argparse
import io
import json
import zipfile

import numpy as np

SUPPORTED_SKIP = {"InputLayer", "Dropout", "Flatten", "Activation"}


def load_keras3(path):
    """Fichier .keras (zip : config.json + model.weights.h5)."""
    import h5py
    with zipfile.ZipFile(path) as z:
        cfg = json.loads(z.read("config.json"))
        h5bytes = z.read("model.weights.h5")
    layers_cfg = cfg["config"]["layers"]
    f = h5py.File(io.BytesIO(h5bytes), "r")
    layers = []
    pending_act = None
    for lc in layers_cfg:
        cls, c = lc["class_name"], lc["config"]
        if cls == "Dense":
            g = f["layers"][c["name"]]["vars"]
            W = np.array(g["0"], dtype=np.float32)
            b = np.array(g["1"], dtype=np.float32) if c.get("use_bias", True) else np.zeros(W.shape[1], np.float32)
            layers.append({"W": W, "b": b, "act": c.get("activation", "linear")})
        elif cls == "Activation":
            if not layers:
                raise ValueError("Activation avant la premiere couche Dense")
            layers[-1]["act"] = c["activation"]
        elif cls in SUPPORTED_SKIP:
            continue
        else:
            raise ValueError(f"Couche non supportee : {cls} (seuls Dense/Dropout/Activation)")
    return layers


def load_h5_legacy(path):
    """Ancien format Keras 2 .h5 (model_config + model_weights)."""
    import h5py
    f = h5py.File(path, "r")
    cfg = json.loads(f.attrs["model_config"] if isinstance(f.attrs["model_config"], str)
                     else f.attrs["model_config"].decode())
    mw = f["model_weights"]
    layers = []
    for lc in cfg["config"]["layers"] if isinstance(cfg["config"], dict) else cfg["config"]:
        cls, c = lc["class_name"], lc["config"]
        if cls == "Dense":
            g = mw[c["name"]]
            names = []
            g.visit(lambda n: names.append(n))
            k = [n for n in names if n.endswith("kernel:0") or n.endswith("kernel")][0]
            bb = [n for n in names if n.endswith("bias:0") or n.endswith("bias")]
            W = np.array(g[k], dtype=np.float32)
            b = np.array(g[bb[0]], dtype=np.float32) if bb else np.zeros(W.shape[1], np.float32)
            layers.append({"W": W, "b": b, "act": c.get("activation", "linear")})
        elif cls == "Activation":
            layers[-1]["act"] = c["activation"]
        elif cls in SUPPORTED_SKIP:
            continue
        else:
            raise ValueError(f"Couche non supportee : {cls}")
    return layers


def load_model(path):
    if zipfile.is_zipfile(path):
        return load_keras3(path)
    return load_h5_legacy(path)


def numpy_predict(layers, mean, std, X):
    h = (X - mean) / std
    for L in layers:
        h = h @ L["W"] + L["b"]
        if L["act"] == "relu":
            h = np.maximum(h, 0)
        elif L["act"] == "softmax":
            h = np.exp(h - h.max(axis=1, keepdims=True))
            h /= h.sum(axis=1, keepdims=True)
        elif L["act"] not in ("linear", None):
            raise ValueError("activation non supportee : " + str(L["act"]))
    return h


ACT_ID = {"linear": 0, "relu": 1, "softmax": 2}


def fmt(arr, per_line=8):
    vals = [f"{v: .9e}f" for v in np.asarray(arr, dtype=np.float32).ravel()]
    lines = [", ".join(vals[i:i + per_line]) for i in range(0, len(vals), per_line)]
    return "    " + ",\n    ".join(lines)


def write_header(path, layers, mean, std, labels, src_name):
    n_in = layers[0]["W"].shape[0]
    n_cls = layers[-1]["W"].shape[1]
    widths = [n_in] + [L["W"].shape[1] for L in layers]
    out = []
    out.append("/* model_weights.h -- GENERE par tools/export_weights.py : ne pas editer */")
    out.append(f"/* source : {src_name} */")
    out.append("#ifndef MODEL_WEIGHTS_H\n#define MODEL_WEIGHTS_H\n")
    out.append(f"#define MODEL_N_INPUT   {n_in}")
    out.append(f"#define MODEL_N_CLASSES {n_cls}")
    out.append(f"#define MODEL_N_LAYERS  {len(layers)}")
    out.append(f"#define MODEL_MAX_WIDTH {max(widths)}")
    out.append("#define MODEL_IS_PLACEHOLDER 0\n")
    out.append("typedef struct { const float *W; const float *b; int n_in; int n_out; int act; } model_layer_t;\n")
    out.append("static const char *const model_labels[MODEL_N_CLASSES] = { " +
               ", ".join(f'"{l}"' for l in labels) + " };\n")
    out.append("static const float model_norm_mean[MODEL_N_INPUT] = {\n" + fmt(mean) + "\n};")
    out.append("static const float model_norm_std[MODEL_N_INPUT] = {\n" + fmt(std) + "\n};\n")
    for i, L in enumerate(layers):
        W_t = L["W"].T  # [sortie][entree]
        out.append(f"/* couche {i} : {L['W'].shape[0]} -> {L['W'].shape[1]}, {L['act']} */")
        out.append(f"static const float model_W{i}[{W_t.size}] = {{\n" + fmt(W_t) + "\n};")
        out.append(f"static const float model_b{i}[{L['b'].size}] = {{\n" + fmt(L['b']) + "\n};\n")
    out.append("static const model_layer_t model_layers[MODEL_N_LAYERS] = {")
    for i, L in enumerate(layers):
        out.append(f"    {{ model_W{i}, model_b{i}, {L['W'].shape[0]}, {L['W'].shape[1]}, "
                   f"{ACT_ID[L['act']]} }},")
    out.append("};\n\n#endif")
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--mean", required=True)
    ap.add_argument("--std", required=True)
    ap.add_argument("--labels", default="yes,no,unknown")
    ap.add_argument("--out", default="sw/src/model_weights.h")
    ap.add_argument("--npz", default=None, help="sauvegarde aussi les poids en .npz (pour uart_capture.py)")
    ap.add_argument("--check-x")
    ap.add_argument("--check-y")
    a = ap.parse_args()

    layers = load_model(a.model)
    mean = np.load(a.mean).astype(np.float32).ravel()
    std = np.load(a.std).astype(np.float32).ravel()
    std = np.where(std == 0, 1.0, std).astype(np.float32)
    labels = [s.strip() for s in a.labels.split(",")]

    n_in, n_cls = layers[0]["W"].shape[0], layers[-1]["W"].shape[1]
    assert mean.size == n_in and std.size == n_in, "taille de normalisation != entree du modele"
    assert len(labels) == n_cls, f"{len(labels)} labels pour {n_cls} classes"
    if layers[-1]["act"] != "softmax":
        print("ATTENTION : la derniere couche n'est pas softmax")

    for i, L in enumerate(layers):
        print(f"couche {i}: {L['W'].shape[0]:4d} -> {L['W'].shape[1]:4d}  {L['act']}")

    if a.check_x:
        X = np.load(a.check_x).astype(np.float32)
        p = numpy_predict(layers, mean, std, X)
        msg = f"prediction numpy sur {len(X)} exemples"
        if a.check_y:
            y = np.load(a.check_y).ravel()
            acc = (p.argmax(1) == y).mean()
            msg += f" : precision = {acc * 100:.2f} %"
            for c in range(n_cls):
                m = y == c
                msg += f" | {labels[c]} {(p[m].argmax(1) == c).mean() * 100:.1f}%"
        print(msg)

    write_header(a.out, layers, mean, std, labels, a.model.replace("\\", "/").split("/")[-1])
    print("ecrit :", a.out)
    if a.npz:
        d = {"mean": mean, "std": std, "labels": np.array(labels)}
        for i, L in enumerate(layers):
            d[f"W{i}"], d[f"b{i}"], d[f"act{i}"] = L["W"], L["b"], np.array(L["act"])
        np.savez(a.npz, **d)
        print("ecrit :", a.npz)


if __name__ == "__main__":
    main()
