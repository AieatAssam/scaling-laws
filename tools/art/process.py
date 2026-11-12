#!/usr/bin/env python3
"""process.py <raw.png> <out.png> --size WxH [--opaque] [--preview DIR]
                [--grid GWxGH] [--cell N] [--scale K] [--outline] [--clean]
                [--canvas WxH] [--stretch] [--speck3] [--frame N]

Turns a codex-generated pixel-art PNG (magenta #FF00FF key) into a game-ready PNG.

Known-grid mode (recommended): give --grid (art pixels, default = SIZE/SCALE) and/or --cell
(raw px per art pixel). The generator was asked for an exact grid, so cells are sampled at
the known period with an edge-aligned offset search. One palette colour per cell (mode over
the cell interior, key pixels excluded), no resampling blur. --scale K then pixel-doubles
(K x K blocks) the art to reach SIZE.

Detection mode (no --grid/--cell): the old freehand-grid fallback: finds the model's own
lattice, else box-samples. Use only for raws without a known grid.

Clean-up (both modes): --clean removes shade specks (a cell whose 4 neighbours agree and
are a near shade of it) for opaque sprites; --outline adds a 1 px #0B0E1A outline around
transparent sprites (fits the art into the size minus 1 px on each side, so nothing clips).
Output is exactly SIZE, palette colours plus full transparency only, nearest sampling only.
Run with tools/art/.venv/bin/python.

Extra steps (all nearest, all palette-only):
  --canvas WxH  nearest-resample the raw to the canvas the prompt asked for, when they differ
                (the model returns e.g. 1672x941 for a 1280x720 request).
  --stretch     no lattice: map the whole raw onto exactly SIZE cells, aspect ignored. For wide
                strips (roof/ground 208x32) that the aspect-preserving path letterboxes.
                Cell with >= half key -> transparent, else mode of its non-key pixels.
  --speck3      opaque only: a cell whose 3x3 window holds <= 2 of its own colour and some other
                colour >= 5 times takes that majority colour (kills 1-cell speckle on backdrops).
  --frame N     floor frame: transparent cells outside the N-px border are filled from the nearest
                opaque edge cell (edges extend to the canvas), then the inner hole is forced transparent.
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
FRINGE_FRAC = 0.35     # a cell is transparent if >= this fraction of it is key (drops mixed fringe cells)
EDGE_TOL = 30          # per-channel-sum change that counts as a cell edge (detection mode)
LATTICE_MIN_R = 0.85   # below this the edges are not a regular lattice (model drew freehand)
EDGE_FRAC = 0.2        # fraction of rows/cols that must show an edge at a position
LATTICE_MIN_CONTRAST = 0.03  # boundary-vs-interior palette-change rate; below this there is no lattice (room probe: 0.04)
SPECK_DIST = 90       # RGB distance: a lone cell this close to its 4 neighbours' colour is noise
OUTLINE = (11, 14, 26)  # palette[0], #0B0E1A


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


def block_mode(idx_block, pal, valid=None):
    """Most common palette colour in a block (pixel-art sampling, no blending)."""
    v = idx_block.ravel() if valid is None else idx_block[valid]
    if v.size == 0:
        return None
    counts = np.bincount(v, minlength=len(pal))
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


# ---------- known-grid mode ----------

def find_lattice(change, n, g, fixed_p=None):
    """Best cell period p and start s along one axis. change[i] = palette-change fraction between
    px i and i+1 over non-key pairs (NaN if none). Score = change rate on cell boundaries minus
    the rate elsewhere: a flat or noisy image scores ~0. The model draws its own cell count, which
    can differ from the requested grid g, so p is searched over plausible counts (0.7g..1.8g)."""
    cands = [fixed_p] if fixed_p else np.arange(n / (1.8 * g), n / (0.7 * g), 0.05)
    best = (n / g, 0.0, -np.inf)
    for p in cands:
        for s in np.arange(0, p, 0.5):
            bi = np.round(s + np.arange(-1, n / p + 2) * p).astype(int) - 1
            bi = np.unique(bi[(bi >= 0) & (bi < n - 1)])
            if bi.size == 0 or bi.size >= n - 1:
                continue
            mask = np.zeros(n - 1, bool)
            mask[bi] = True
            on, off = np.nanmean(change[mask]), np.nanmean(change[~mask])
            score = on - off - 1e-4 * s
            if score > best[2]:
                best = (p, s, score)
    return best


def cell_bounds(p, s, n):
    """[start, end) pixel ranges of cells at s + k*p that overlap the image [0, n)."""
    b = s + np.arange(-1, int(n / p) + 3) * p
    out = []
    for lo, hi in zip(b[:-1], b[1:]):
        if (lo + hi) / 2 < 0 or (lo + hi) / 2 > n:
            continue
        out.append((max(0, int(round(lo))), min(n, int(round(hi)))))
    return [(a, b_) for a, b_ in out if b_ > a]


def sample_known(rgb, bg, idx, pal, gw, gh, cell):
    """Sample the image as a regular cell lattice, then map the cell grid to exactly gh x gw by
    cell-level mode. Returns (colours[gh,gw,3], keyed[gh,gw], info). Never resamples pixels."""
    H, W = rgb.shape[:2]
    vx = ~bg[:, 1:] & ~bg[:, :-1]
    vy = ~bg[1:, :] & ~bg[:-1, :]
    cx = np.where(vx.sum(0) > 0, ((idx[:, 1:] != idx[:, :-1]) & vx).sum(0) / np.maximum(vx.sum(0), 1), np.nan)
    cy = np.where(vy.sum(1) > 0, ((idx[1:, :] != idx[:-1, :]) & vy).sum(1) / np.maximum(vy.sum(1), 1), np.nan)
    px, sx, scx = find_lattice(cx, W, gw, fixed_p=cell)
    py, sy, scy = find_lattice(cy, H, gh, fixed_p=cell)
    if min(scx, scy) < LATTICE_MIN_CONTRAST:  # no real lattice: sample the requested grid directly
        print(f"warning: no regular cell lattice (contrast {scx:.2f}/{scy:.2f}); box-sampling the {gw}x{gh} grid")
        px, sx, py, sy = W / gw, 0.0, H / gh, 0.0
    xr, yr = cell_bounds(px, sx, W), cell_bounds(py, sy, H)
    ny, nx = len(yr), len(xr)
    cidx = np.full((ny, nx), -1)
    for j, (y0, y1) in enumerate(yr):
        m_y = max(1, int((y1 - y0) * 0.15))
        for i, (x0, x1) in enumerate(xr):
            if bg[y0:y1, x0:x1].mean() >= FRINGE_FRAC:
                continue
            m_x = max(1, int((x1 - x0) * 0.15))
            iy0, iy1, ix0, ix1 = y0 + m_y, y1 - m_y, x0 + m_x, x1 - m_x
            if iy1 <= iy0 or ix1 <= ix0:
                iy0, iy1, ix0, ix1 = y0, y1, x0, x1
            inner_bg = bg[iy0:iy1, ix0:ix1]
            inner = idx[iy0:iy1, ix0:ix1]
            v = inner[~inner_bg]
            if v.size:
                cidx[j, i] = np.bincount(v, minlength=len(pal)).argmax()
    info = f"cells {nx}x{ny} (cell {px:.2f}x{py:.2f}px, contrast {scx:.2f}/{scy:.2f})"
    cidx = map_cells(cidx, gh, gw)
    return pal[np.maximum(cidx, 0)], cidx < 0, info


def map_cells(cidx, gh, gw):
    """Cell grid (ny x nx, -1 = key) -> exactly gh x gw by mode over the cells each target covers."""
    ny, nx = cidx.shape
    if (ny, nx) == (gh, gw):
        return cidx
    print(f"note: model drew {nx}x{ny} cells, target grid {gw}x{gh}: cell-level mode mapping")
    ye, xe = np.linspace(0, ny, gh + 1), np.linspace(0, nx, gw + 1)
    out = np.full((gh, gw), -1)
    for j in range(gh):
        ya, yb = int(ye[j]), max(int(ye[j]) + 1, int(ye[j + 1]))
        for i in range(gw):
            xa, xb = int(xe[i]), max(int(xe[i]) + 1, int(xe[i + 1]))
            blk = cidx[ya:yb, xa:xb].ravel()
            if (blk < 0).mean() >= 0.5:
                continue
            out[j, i] = np.bincount(blk[blk >= 0]).argmax()
    return out


def clean_specks(cols, keyed, pal):
    """Replace a cell by its neighbours' colour when all 4 neighbours agree and are a near shade."""
    if cols.shape[0] < 3 or cols.shape[1] < 3:
        return cols, 0
    out = cols.copy()
    n = 0
    H, W = keyed.shape
    for j in range(1, H - 1):
        for i in range(1, W - 1):
            if keyed[j, i]:
                continue
            nb = [(j - 1, i), (j + 1, i), (j, i - 1), (j, i + 1)]
            if any(keyed[y, x] for y, x in nb):
                continue
            c0 = cols[nb[0]]
            if all(np.array_equal(cols[y, x], c0) for y, x in nb[1:]) and \
                    not np.array_equal(cols[j, i], c0) and \
                    np.linalg.norm(cols[j, i] - c0) <= SPECK_DIST:
                out[j, i] = c0
                n += 1
    return out, n


def fit_known(cols, keyed, tw, th, transparent):
    """Fit the sampled grid into exactly th x tw art pixels. Never upscales: pads or nearest-shrinks."""
    if transparent:
        solid = ~keyed
        rows, colsk = np.where(solid.any(axis=1))[0], np.where(solid.any(axis=0))[0]
        if len(rows) == 0:
            sys.exit("no sprite content found in the cell grid")
        cols, keyed = cols[rows[0]:rows[-1] + 1, colsk[0]:colsk[-1] + 1], keyed[rows[0]:rows[-1] + 1, colsk[0]:colsk[-1] + 1]
    ch, cw = keyed.shape
    if cw > tw or ch > th:
        scale = min(tw / cw, th / ch)
        nw, nh = max(1, int(cw * scale)), max(1, int(ch * scale))
        print(f"warning: content {cw}x{ch} larger than {tw}x{th}; nearest-shrunk to {nw}x{nh}")
        yi = np.minimum((np.arange(nh) + 0.5) * ch / nh, ch - 1).astype(int)
        xi = np.minimum((np.arange(nw) + 0.5) * cw / nw, cw - 1).astype(int)
        cols, keyed, ch, cw = cols[yi][:, xi], keyed[yi][:, xi], nh, nw
    out_c = np.zeros((th, tw, 3))
    out_k = np.ones((th, tw), bool)
    ox, oy = (tw - cw) // 2, (th - ch) // 2  # centred pad
    out_c[oy:oy + ch, ox:ox + cw] = cols
    out_k[oy:oy + ch, ox:ox + cw] = keyed
    return out_c, ~out_k


def resample_canvas(img, cw, ch):
    """Nearest resample of the raw to the requested canvas (no-op when it already matches)."""
    if img.shape[1] == cw and img.shape[0] == ch:
        return img
    print(f"note: raw {img.shape[1]}x{img.shape[0]} -> canvas {cw}x{ch} (nearest)")
    return np.asarray(Image.fromarray(img).resize((cw, ch), Image.Resampling.NEAREST))


def stretch_grid(img, pal, a, W, H):
    """Whole raw -> exactly H x W cells, aspect ignored, no lattice search. Returns (colours, opaque)."""
    rgb = img[..., :3]
    bg = np.zeros(img.shape[:2], bool) if a.opaque else key_mask(rgb)
    if not a.opaque:  # keyed input: crop to the content first, else the margin wastes the strip
        y0, y1, x0, x1 = content_bbox(bg)
        rgb, bg = rgb[y0:y1, x0:x1], bg[y0:y1, x0:x1]
        print(f"stretch: content crop x{x0}-{x1} y{y0}-{y1}")
    idx = palette_index(rgb, pal)
    h, w = rgb.shape[:2]
    ys, xs = np.linspace(0, h, H + 1).astype(int), np.linspace(0, w, W + 1).astype(int)
    cols = np.zeros((H, W, 3))
    keyed = np.zeros((H, W), bool)
    for j in range(H):
        y0, y1 = ys[j], max(ys[j + 1], ys[j] + 1)
        for i in range(W):
            x0, x1 = xs[i], max(xs[i + 1], xs[i] + 1)
            kb = bg[y0:y1, x0:x1]
            keyed[j, i] = kb.mean() >= 0.5
            v = idx[y0:y1, x0:x1][~kb]
            if v.size:
                cols[j, i] = pal[np.bincount(v, minlength=len(pal)).argmax()]
    print(f"stretch: raw {w}x{h} -> {W}x{H} cells, {int(keyed.sum())} keyed")
    if a.clean:
        cols, n = clean_specks(cols, keyed, pal)
        print(f"clean: {n} speck cell(s) fixed")
    return cols, ~keyed


def speck3(cols, opaque):
    """3x3 majority on opaque cells (see module docstring). Same rule as the backdrop post-fix."""
    k = (cols[..., 0].astype(np.int64) * 65536 + cols[..., 1].astype(np.int64) * 256 + cols[..., 2].astype(np.int64))
    H, W = k.shape
    o = k.copy()
    n = 0
    for y in range(H):
        for x in range(W):
            if not opaque[y, x]:
                continue
            win = k[max(0, y - 1):y + 2, max(0, x - 1):x + 2].ravel()
            vals, cnt = np.unique(win, return_counts=True)
            if (win == k[y, x]).sum() <= 2 and cnt.max() >= 5:
                o[y, x] = vals[cnt.argmax()]
                n += 1
    out = np.stack([o // 65536, (o // 256) % 256, o % 256], -1).astype(float)
    print(f"speck3: {n} cell(s) fixed")
    return out, opaque


def frame_fix(cols, opaque, border):
    """Floor frame: extend the frame's outer edge to the canvas, then force the inner hole transparent."""
    H, W = opaque.shape
    ys, xs = np.where(opaque)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    yy, xx = np.mgrid[0:H, 0:W]
    hole = (xx >= border) & (xx < W - border) & (yy >= border) & (yy < H - border)
    fill = ~opaque & ~hole
    cy, cx = np.clip(yy, y0, y1)[fill], np.clip(xx, x0, x1)[fill]
    out_c, out_o = cols.copy(), opaque.copy()
    out_c[fill] = cols[cy, cx]
    out_o[fill] = opaque[cy, cx]
    out_o[hole] = False
    print(f"frame: bbox x{x0}-{x1} y{y0}-{y1}, hole {W - 2 * border}x{H - 2 * border} forced transparent")
    return out_c, out_o


def add_outline(cols, opaque):
    """1 px dark outline on transparent cells that touch the sprite (4-neighbourhood)."""
    pad = np.pad(opaque, 1)
    touch = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    out_c = cols.copy()
    out_c[touch & ~opaque] = OUTLINE
    return out_c, opaque | touch


def known_grid(img, pal, a, W, H, scale):
    gw, gh = (int(v) for v in a.grid.lower().split("x")) if a.grid else (W // scale, H // scale)
    if W % scale or H % scale:
        sys.exit("--size must be divisible by --scale")
    rgb = img[..., :3]
    bg = np.zeros(img.shape[:2], bool) if a.opaque else key_mask(rgb)
    idx = palette_index(rgb, pal)
    # cell size: --cell if given, else raw size / grid (sample_known decides)
    cols, keyed, info = sample_known(rgb, bg, idx, pal, gw, gh, a.cell)
    print(f"known grid {gw}x{gh}: {info}")
    if a.clean:
        cols, n = clean_specks(cols, keyed, pal)
        print(f"clean: {n} speck cell(s) fixed")
    tw, th = W // scale, H // scale
    if a.opaque:
        if (gw, gh) != (tw, th):
            print(f"warning: opaque grid {gw}x{gh} != target {tw}x{th}; nearest-resampled")
        return fit_known(cols, keyed, tw, th, transparent=False)  # (colours, opaque mask)
    if a.outline:
        cols_in, op_in = fit_known(cols, keyed, tw - 2, th - 2, transparent=True)
        return add_outline(*_pad2(cols_in, op_in))
    return fit_known(cols, keyed, tw, th, transparent=True)


def _pad2(cols, opaque):
    return np.pad(cols, ((1, 1), (1, 1), (0, 0))), np.pad(opaque, 1)


def scale_up(cols, opaque, scale):
    if scale == 1:
        return cols, opaque
    return np.repeat(np.repeat(cols, scale, 0), scale, 1), np.repeat(np.repeat(opaque, scale, 0), scale, 1)


# ---------- detection mode (fallback for raws without a known grid) ----------

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


def detect_grid(img, pal, a, W, H):
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
    d = ((out_rgb[..., None, :] - pal[None, None, :, :]) ** 2).sum(-1)
    q = pal[d.argmin(-1)]
    return q, out_a


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--size", required=True, help="WxH target, e.g. 192x128")
    ap.add_argument("--opaque", action="store_true")
    ap.add_argument("--preview", help="dir to write a x6 nearest preview into")
    ap.add_argument("--grid", help="art pixels WxH the model drew (default SIZE/SCALE); enables known-grid mode")
    ap.add_argument("--cell", type=float, help="raw px per art pixel (enables known-grid mode)")
    ap.add_argument("--scale", type=int, default=1, help="integer pixel-doubling of the art after sampling")
    ap.add_argument("--outline", action="store_true", help="1 px #0B0E1A outline (transparent sprites)")
    ap.add_argument("--clean", action="store_true", help="remove shade specks (known-grid and stretch modes)")
    ap.add_argument("--canvas", help="WxH the raw should be; nearest-resampled first if it differs")
    ap.add_argument("--stretch", action="store_true", help="map the whole raw onto SIZE cells, aspect ignored (strips)")
    ap.add_argument("--speck3", action="store_true", help="3x3 majority speck filter (opaque only, backdrops)")
    ap.add_argument("--frame", type=int, help="floor frame: N-px border, extend edges, force the inner hole transparent")
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.lower().split("x"))
    if a.scale < 1 or W % a.scale or H % a.scale:
        sys.exit("--size must be divisible by --scale")
    if a.stretch and a.scale != 1:
        sys.exit("--stretch does not combine with --scale")
    if a.speck3 and not a.opaque:
        sys.exit("--speck3 is for opaque images (--opaque)")

    img = np.asarray(Image.open(a.raw).convert("RGB"))
    if a.canvas:
        cw, ch = (int(v) for v in a.canvas.lower().split("x"))
        img = resample_canvas(img, cw, ch)
    pal = load_palette()
    if a.stretch:
        cols, opaque = stretch_grid(img, pal, a, W, H)
        q, out_a = cols.astype(np.uint8), opaque
    elif a.grid or a.cell:
        cols, opaque = known_grid(img, pal, a, W, H, a.scale)
        if a.speck3:
            cols, opaque = speck3(cols, opaque)
        if a.frame:
            cols, opaque = frame_fix(cols, opaque, a.frame)
        cols, opaque = scale_up(cols, opaque, a.scale)
        q, out_a = cols.astype(np.uint8), opaque
    else:
        if a.scale != 1:
            sys.exit("--scale needs --grid or --cell")
        q, out_a = detect_grid(img, pal, a, W, H)
        q = q.astype(np.uint8)

    rgba = np.dstack([q, (out_a * 255).astype(np.uint8)])
    rgba[~out_a, :3] = np.array(pal[0], np.uint8)  # transparent pixels: palette colour, alpha 0
    res = Image.fromarray(rgba, "RGBA")

    # self-check: exact size, only palette colours, alpha only 0 or 255
    assert res.size == (W, H), f"size {res.size} != {W}x{H}"
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
