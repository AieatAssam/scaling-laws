#!/usr/bin/env python3
"""process.py <raw.png> <out.png> --size WxH [--opaque] [--preview DIR]

Turns a codex-generated pixel-art PNG (magenta #FF00FF key, fake big pixels) into a
game-ready PNG: detects the pixel grid, samples one colour per cell, crops to the
content, fits to WxH (aspect kept, transparent pad; --opaque = exact resize), keys
magenta to alpha, and quantises to art/palette.hex. Run with tools/art/.venv/bin/python.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PALETTE_PATH = os.path.join(HERE, "..", "..", "art", "palette.hex")
KEY = np.array([255, 0, 255])
KEY_TOL = 120          # RGB distance from #FF00FF that counts as background (covers pink fringe)
EDGE_TOL = 30          # per-channel-sum change that counts as a cell edge
LATTICE_MIN_R = 0.85   # below this the edges are not a regular lattice (model drew freehand)
EDGE_FRAC = 0.2        # fraction of rows/cols that must show an edge at a position


def load_palette():
    cols = [l.strip() for l in open(PALETTE_PATH) if l.strip()]
    assert len(cols) == 32 and all(len(c) == 6 for c in cols), "palette.hex: need 32 RRGGBB lines"
    assert "FF00FF" not in [c.upper() for c in cols], "palette must not contain the key colour"
    return np.array([[int(c[i:i + 2], 16) for i in (0, 2, 4)] for c in cols], dtype=float)


def palette_index(rgb, pal):
    """Nearest palette index per pixel (loop over palette keeps memory small)."""
    f = rgb.astype(np.float32)
    best = np.full(f.shape[:2], np.inf, np.float32)
    idx = np.zeros(f.shape[:2], np.int64)
    for k, c in enumerate(pal.astype(np.float32)):
        d = ((f - c) ** 2).sum(-1)
        m = d < best
        best[m], idx[m] = d[m], k
    return idx


def block_mode(idx_block, pal):
    """Most common palette colour in a block (pixel-art sampling, no blending)."""
    counts = np.bincount(idx_block.ravel(), minlength=len(pal))
    return pal[counts.argmax()]


def key_mask(rgb):
    """True where the pixel is magenta-ish background."""
    return np.linalg.norm(rgb.astype(float) - KEY, axis=-1) < KEY_TOL


def content_bbox(bg):
    rows = np.where((~bg).sum(axis=1) >= 2)[0]
    cols = np.where((~bg).sum(axis=0) >= 2)[0]
    if len(rows) == 0 or len(cols) == 0:
        sys.exit("no sprite content found (everything keyed as background)")
    return rows[0], rows[-1] + 1, cols[0], cols[-1] + 1


def edge_positions(rgb, axis):
    """Pixel indices where a new cell starts, along axis (1 = x, 0 = y)."""
    a = rgb.astype(int)
    d = np.abs(np.diff(a, axis=axis)).sum(axis=-1) > EDGE_TOL
    frac = d.mean(axis=1 - axis) if axis == 1 else d.mean(axis=1)
    pos = np.where(frac > EDGE_FRAC)[0] + 1
    return pos


def cluster(pos, n, gap=3):
    """Merge jittered duplicate edges (within gap px) and drop crop-border artifacts."""
    pos = [int(v) for v in pos if 2 <= v <= n - 2]
    out, grp = [], []
    for v in pos:
        if grp and v - grp[-1] > gap:
            out.append(np.mean(grp)); grp = []
        grp.append(v)
    if grp:
        out.append(np.mean(grp))
    return np.array(out)


def find_period(pos, n):
    """Cell period + phase: coarse lattice search, then least-squares refinement."""
    pos = cluster(pos, n)
    if len(pos) < 3:
        return 1.0, 0.0, 0.0, 99.0  # too smooth for a lattice: caller falls back to box sampling
    ps = np.arange(3.0, n / 4, 0.02)  # need at least ~4 cells across
    z = np.exp(2j * np.pi * pos[None, :] / ps[:, None]).mean(axis=1)
    R = np.abs(z)
    best = R.max()
    i = np.where(R >= 0.97 * best)[0][-1]  # largest period that still fits: smaller ones are sub-lattices
    p = ps[i]
    k = np.round((pos - pos[0]) / p)
    for _ in range(3):  # refine: fit pos = a + p*k, re-assign k
        A = np.vstack([np.ones_like(k), k]).T
        a, p = np.linalg.lstsq(A, pos, rcond=None)[0]
        k = np.round((pos - a) / p)
    resid = np.abs(pos - (a + p * k)).mean()
    return p, a % p, best, resid


def cell_edges(period, offset, n):
    k0 = int(np.floor(-offset / period))
    k1 = int(np.ceil((n - offset) / period)) + 1
    e = offset + period * np.arange(k0, k1 + 1)
    e = e[(e > -0.5) & (e < n + 0.5)]
    e = np.clip(e, 0, n)
    return [(int(np.ceil(a)), int(np.floor(b))) for a, b in zip(e[:-1], e[1:])
            if b - a >= 0.5 * period]


def sample_grid(rgb, bg, px, py, idx, pal):
    """One median colour + bg flag per cell. px/py = (period, offset) along x / y."""
    H, W = rgb.shape[:2]
    xs = cell_edges(px[0], px[1], W)
    ys = cell_edges(py[0], py[1], H)
    m_x, m_y = max(1, int(px[0] * 0.2)), max(1, int(py[0] * 0.2))
    cols = np.zeros((len(ys), len(xs), 3))
    keyed = np.zeros((len(ys), len(xs)))
    for j, (y0, y1) in enumerate(ys):
        for i, (x0, x1) in enumerate(xs):
            sy0, sy1 = y0 + m_y, y1 - m_y
            sx0, sx1 = x0 + m_x, x1 - m_x
            if sy1 <= sy0 or sx1 <= sx0:
                sy0, sy1, sx0, sx1 = y0, y1, x0, x1
            cols[j, i] = block_mode(idx[sy0:sy1, sx0:sx1], pal)
            keyed[j, i] = bg[sy0:sy1, sx0:sx1].mean()
    return cols, keyed >= 0.5


def fit_dims(nx, ny, W, H):
    """Largest (tw, th) with the same aspect as nx x ny that fits inside W x H."""
    scale = min(W / nx, H / ny)
    return max(1, min(W, round(nx * scale))), max(1, min(H, round(ny * scale)))


def box_sample(rgb, bg, th, tw, idx, pal):
    """Median colour per output pixel over its source box (for irregular/non-lattice images)."""
    H, W = rgb.shape[:2]
    ys = np.linspace(0, H, th + 1).astype(int)
    xs = np.linspace(0, W, tw + 1).astype(int)
    cols = np.zeros((th, tw, 3))
    keyed = np.zeros((th, tw), bool)
    for j in range(th):
        for i in range(tw):
            y1, x1 = max(ys[j + 1], ys[j] + 1), max(xs[i + 1], xs[i] + 1)
            cols[j, i] = block_mode(idx[ys[j]:y1, xs[i]:x1], pal)
            keyed[j, i] = bg[ys[j]:y1, xs[i]:x1].mean() >= 0.5
    return cols, keyed


def resample(grid, th, tw):
    ny, nx = grid.shape[:2]
    yi = np.minimum((np.arange(th) + 0.5) * ny / th, ny - 1).astype(int)
    xi = np.minimum((np.arange(tw) + 0.5) * nx / tw, nx - 1).astype(int)
    return grid[yi][:, xi]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--size", required=True, help="WxH target, e.g. 96x64")
    ap.add_argument("--opaque", action="store_true")
    ap.add_argument("--preview", help="dir to write a x6 nearest preview into")
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.lower().split("x"))

    img = np.asarray(Image.open(a.raw).convert("RGB"))
    pal = load_palette()
    bg_full = np.zeros(img.shape[:2], bool) if a.opaque else key_mask(img)
    y0, y1, x0, x1 = (0, img.shape[0], 0, img.shape[1]) if a.opaque else content_bbox(bg_full)
    rgb, bg = img[y0:y1, x0:x1], bg_full[y0:y1, x0:x1]
    idx = palette_index(rgb, pal)

    px = find_period(edge_positions(rgb, 1), rgb.shape[1])
    py = find_period(edge_positions(rgb, 0), rgb.shape[0])
    lattice_ok = min(px[2], py[2]) >= LATTICE_MIN_R and max(px[3], py[3]) <= 2.0
    if lattice_ok:
        cols, keyed = sample_grid(rgb, bg, px[:2], py[:2], idx, pal)
        print(f"lattice: cell x={px[0]:.2f} y={py[0]:.2f}px (R={min(px[2], py[2]):.2f}); grid {cols.shape[1]}x{cols.shape[0]}")
    else:
        print(f"no regular lattice (R={px[2]:.2f}/{py[2]:.2f}); box-sampling to target size")
        ph, pw = (H, W) if a.opaque else fit_dims(rgb.shape[1], rgb.shape[0], W, H)[::-1]
        cols, keyed = box_sample(rgb, bg, ph, pw, idx, pal)

    if not a.opaque and lattice_ok:
        solid = ~keyed
        rows, colsk = np.where(solid.any(axis=1))[0], np.where(solid.any(axis=0))[0]
        cols, keyed = cols[rows[0]:rows[-1] + 1, colsk[0]:colsk[-1] + 1], keyed[rows[0]:rows[-1] + 1, colsk[0]:colsk[-1] + 1]
    if not a.opaque:
        ny, nx = cols.shape[:2]
        tw, th = fit_dims(nx, ny, W, H)
        g_rgb, g_key = resample(cols, th, tw), resample(keyed, th, tw)
        out_rgb = np.zeros((H, W, 3))
        out_a = np.zeros((H, W), bool)
        ox, oy = (W - tw) // 2, (H - th) // 2
        out_rgb[oy:oy + th, ox:ox + tw] = g_rgb
        out_a[oy:oy + th, ox:ox + tw] = ~g_key
    else:
        out_rgb = resample(cols, H, W)
        out_a = np.ones((H, W), bool)

    # quantise every opaque pixel to the nearest palette colour
    d = ((out_rgb[..., None, :] - pal[None, None, :, :]) ** 2).sum(-1)
    q = pal[d.argmin(-1)].astype(np.uint8)
    q[~out_a] = pal[0].astype(np.uint8)  # transparent pixels: palette colour, alpha 0
    rgba = np.dstack([q, (out_a * 255).astype(np.uint8)])
    res = Image.fromarray(rgba, "RGBA")

    # self-check: exact size, only palette colours, alpha only 0 or 255
    assert res.size == (W, H)
    alpha = rgba[..., 3]
    assert set(np.unique(alpha)) <= {0, 255}
    vis = rgba[alpha == 255][:, :3]
    assert len(vis) == 0 or set(map(tuple, np.unique(vis, axis=0))) <= set(map(tuple, pal.astype(np.uint8)))
    res.save(a.out)
    print(f"wrote {a.out} {W}x{H}, {int((alpha == 255).sum())} opaque px")

    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        bgc = Image.new("RGBA", (W, H), (128, 128, 128, 255))
        bgc.alpha_composite(res)
        name = os.path.splitext(os.path.basename(a.out))[0]
        bgc.resize((W * 6, H * 6), Image.Resampling.NEAREST).save(os.path.join(a.preview, f"{name}_x6.png"))


if __name__ == "__main__":
    main()
