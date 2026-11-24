"""Leitura dos dados base do MakeHuman (CC0): malha, alvos de forma, esqueleto e pesos.

Os dados vêm de https://github.com/makehumancommunity/makehuman (pasta makehuman/data),
liberados como CC0 (domínio público). Unidades do MakeHuman: decímetros, eixo Y para cima.
"""
import json
import os
import numpy as np


class BaseMesh:
    def __init__(self, data_dir):
        self.data_dir = data_dir
        self.coords = []
        self.uvs = []
        self.faces = []      # lista de (índices de vértice, índices de UV, grupo)
        groups = []
        group = None
        with open(os.path.join(data_dir, "3dobjs", "base.obj")) as f:
            for line in f:
                if line.startswith("v "):
                    self.coords.append([float(x) for x in line.split()[1:4]])
                elif line.startswith("vt "):
                    self.uvs.append([float(x) for x in line.split()[1:3]])
                elif line.startswith("g "):
                    group = line.split()[1]
                elif line.startswith("f "):
                    vi, ti = [], []
                    for tok in line.split()[1:]:
                        parts = tok.split("/")
                        vi.append(int(parts[0]) - 1)
                        ti.append(int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1)
                    self.faces.append((vi, ti, group))
        self.coords = np.array(self.coords, dtype=np.float64)
        self.uvs = np.array(self.uvs, dtype=np.float64)

    def load_target(self, rel_path):
        path = os.path.join(self.data_dir, "targets", rel_path)
        idx, delta = [], []
        with open(path) as f:
            for line in f:
                if not line.strip() or line.startswith("#"):
                    continue
                p = line.split()
                idx.append(int(p[0]))
                delta.append([float(p[1]), float(p[2]), float(p[3])])
        return np.array(idx, dtype=np.int64), np.array(delta, dtype=np.float64)

    def apply_targets(self, weighted_targets):
        """weighted_targets: lista de (caminho relativo, peso)."""
        for rel, w in weighted_targets:
            if w == 0:
                continue
            idx, delta = self.load_target(rel)
            if len(idx):
                self.coords[idx] += delta * w

    def group_faces(self, name):
        return [f for f in self.faces if f[2] == name]

    def group_vertices(self, name):
        s = set()
        for vi, _, g in self.faces:
            if g == name:
                s.update(vi)
        return sorted(s)


class Skeleton:
    def __init__(self, data_dir, base):
        with open(os.path.join(data_dir, "rigs", "default.mhskel")) as f:
            d = json.load(f)
        self.bones = d["bones"]
        self.planes = d.get("planes", {})
        self.joint_pos = {}
        for name, verts in d["joints"].items():
            self.joint_pos[name] = base.coords[verts].mean(axis=0)
        with open(os.path.join(data_dir, "rigs", "default_weights.mhw")) as f:
            self.weights = json.load(f)["weights"]  # osso -> [[vértice, peso], ...]

    def head(self, bone):
        return self.joint_pos[self.bones[bone]["head"]]

    def tail(self, bone):
        return self.joint_pos[self.bones[bone]["tail"]]

    def plane_normal(self, bone):
        plane = self.bones[bone].get("rotation_plane")
        if not plane or plane not in self.planes:
            return None
        a, b, c = (self.joint_pos[j] for j in self.planes[plane])
        n = np.cross(b - a, c - a)
        ln = np.linalg.norm(n)
        return n / ln if ln > 1e-9 else None


def load_mhclo(path, base):
    """Ajusta um proxy/roupa do MakeHuman (.mhclo) à malha base já deformada."""
    folder = os.path.dirname(path)
    obj_file, refs, scales, z_depth = None, [], {}, 50
    reading = False
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p or p[0].startswith("#"):
                continue
            if p[0] == "obj_file":
                obj_file = p[1]
            elif p[0] in ("x_scale", "y_scale", "z_scale"):
                scales[p[0][0]] = (int(p[1]), int(p[2]), float(p[3]))
            elif p[0] == "verts":
                reading = True
            elif reading:
                try:
                    int(p[0])
                    refs.append(p)
                except ValueError:
                    reading = False
    def axis_scale(k, axis):
        if k not in scales:
            return 1.0
        a, b, ref = scales[k]
        return abs(base.coords[a][axis] - base.coords[b][axis]) / ref
    s = np.array([axis_scale("x", 0), axis_scale("y", 1), axis_scale("z", 2)])
    coords = []
    for r in refs:
        if len(r) == 1:
            coords.append(base.coords[int(r[0])])
        else:
            v = [int(x) for x in r[0:3]]
            w = [float(x) for x in r[3:6]]
            o = np.array([float(x) for x in r[6:9]])
            coords.append(sum(base.coords[v[i]] * w[i] for i in range(3)) + o * s)
    # lê a malha do proxy
    verts_uv, faces = [], []
    uvs = []
    with open(os.path.join(folder, obj_file)) as f:
        for line in f:
            if line.startswith("vt "):
                uvs.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("f "):
                vi, ti = [], []
                for tok in line.split()[1:]:
                    parts = tok.split("/")
                    vi.append(int(parts[0]) - 1)
                    ti.append(int(parts[1]) - 1 if len(parts) > 1 and parts[1] else -1)
                faces.append((vi, ti))
    return np.array(coords), np.array(uvs), faces
