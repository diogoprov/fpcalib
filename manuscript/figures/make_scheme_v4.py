"""Schematic of the fpcalib simulation (replaces Fig1_simulation_scheme).
Pictograms + mini-plots + design map; text only as labels."""
import math, random

W, H = 2060, 1250
INK, MUTED, FAINT, RULE = "#2b2b2b", "#6b6b6b", "#a8a8a8", "#d9d9d9"
BLUE, ORANGE, GREEN = "#2A6FB0", "#C8691C", "#2F9E6E"
FONT = "Helvetica, Arial, FreeSans, sans-serif"
out = []
def add(s): out.append(s)
def text(x, y, s, size=22, fill=INK, anchor="start", weight="normal", style="normal"):
    size = max(23, round(size * 1.25))
    add(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" fill="{fill}" '
        f'text-anchor="{anchor}" font-weight="{weight}" font-style="{style}">{s}</text>')
def panel(x, y, s):
    text(x, y, s, size=34, weight="bold")
def arrow(x1, y1, x2, y2, col=MUTED, w=2.5):
    add(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{w}" marker-end="url(#ah)"/>')

# ---------------------------------------------------------------- glyphs
# Caprimulgus silhouette: PhyloPic image 19899811-afff-4ba8-8084-cc7fe762da7e,
# by Ferran Sayol, CC0 1.0 (public domain). viewBox 1536 x 675, faces right.
CAPRI_D = """M12682 6739 c-160 -15 -268 -44 -477 -126 -279 -110 -610 -294 -907 -505 -210 -149 -490 -367 -638 -498 -277 -243 -337 -278 -605 -360 -230 -70 -432 -143 -725 -260 -135 -54 -408 -159 -608 -234 -481 -182 -635 -246 -897 -375 -277 -137 -277 -137 -607 -171 -212 -22 -246 -28 -860 -164 -466 -104 -653 -138 -1138 -211 -206 -30 -537 -82 -735 -115 -198 -33 -578 -87 -845 -120 -629 -78 -879 -121 -1170 -205 -161 -47 -592 -201 -670 -240 -135 -68 -233 -162 -309 -296 -75 -134 -20 -249 165 -342 58 -29 157 -57 204 -57 l32 0 -36 -40 c-46 -51 -48 -88 -7 -123 54 -45 112 -52 376 -47 382 8 1504 5 1568 -4 72 -10 68 -16 -50 -78 -191 -101 -350 -148 -846 -248 -191 -39 -400 -86 -465 -106 -182 -55 -743 -241 -1232 -409 -245 -84 -544 -185 -665 -224 -375 -122 -535 -219 -535 -325 0 -81 233 -225 510 -316 180 -59 222 -64 531 -57 375 7 593 34 1294 157 544 95 579 98 1540 140 345 15 467 25 870 75 786 97 1276 137 2280 186 497 24 956 22 1170 -5 536 -68 1533 -236 1755 -296 l43 -11 -33 -34 c-18 -19 -64 -50 -102 -70 -37 -20 -66 -40 -63 -46 10 -16 136 -48 270 -69 152 -24 212 -49 380 -159 127 -83 172 -99 398 -141 264 -48 334 -76 409 -159 l45 -50 30 19 c40 24 73 67 73 96 0 37 -63 98 -171 164 -54 33 -99 64 -99 67 0 12 111 -8 283 -52 142 -36 196 -45 263 -45 46 0 84 2 84 5 0 19 -58 114 -91 150 l-40 43 73 7 c181 17 351 64 677 187 113 42 273 92 410 128 124 32 265 72 313 90 236 86 455 298 766 744 124 178 201 324 227 431 28 113 52 168 137 308 129 213 160 284 193 444 44 213 37 448 -26 812 -90 517 -91 526 -92 716 l-2 180 32 67 c45 96 147 241 338 483 191 242 248 303 313 336 42 22 60 24 177 24 72 0 145 -3 164 -8 l34 -7 -6 54 c-12 121 -90 211 -264 308 -187 104 -263 157 -318 226 -110 136 -552 418 -815 519 -58 23 -181 77 -275 121 -203 95 -246 110 -356 122 -98 11 -527 11 -647 -1z"""
def bird(cx, cy, s=1.0, fill=INK, dashed=False):
    k = 0.05 * s                       # 1536 units -> ~77 px wide at s = 1
    w, h = 1536 * k, 675 * k
    st = (f'fill="white" stroke="{fill}" stroke-width="2.2" stroke-dasharray="5 2.5" '
          f'vector-effect="non-scaling-stroke"') if dashed else f'fill="{fill}"'
    add(f'<g transform="translate({cx - w/2:.1f},{cy - h/2:.1f}) scale({k:.4f})">'
        f'<g transform="translate(0,675) scale(0.1,-0.1)"><path d="{CAPRI_D}" {st}/></g></g>')
def recorder(cx, cy):
    add(f'<rect x="{cx-11}" y="{cy-16}" width="22" height="30" rx="4" fill="white" stroke="{INK}" stroke-width="2.2"/>')
    for dy in (-8, -2, 4):
        add(f'<line x1="{cx-5}" y1="{cy+dy}" x2="{cx+5}" y2="{cy+dy}" stroke="{INK}" stroke-width="1.6"/>')
    add(f'<line x1="{cx}" y1="{cy+14}" x2="{cx}" y2="{cy+40}" stroke="{INK}" stroke-width="2.2"/>')
def headphones(cx, cy, col=GREEN):
    add(f'<path d="M{cx-14},{cy+6} v-6 a14,14 0 0 1 28,0 v6" fill="none" stroke="{col}" stroke-width="3"/>'
        f'<rect x="{cx-18}" y="{cy+2}" width="8" height="12" rx="2" fill="{col}"/>'
        f'<rect x="{cx+10}" y="{cy+2}" width="8" height="12" rx="2" fill="{col}"/>')
def cell(x, y, kind, s=16):
    if kind == "T":
        add(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="2" fill="{BLUE}"/>')
    elif kind == "F":
        add(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="2" fill="{ORANGE}"/>'
            f'<line x1="{x+3}" y1="{y+s-3}" x2="{x+s-3}" y2="{y+3}" stroke="white" stroke-width="2"/>')
    else:
        add(f'<rect x="{x+0.75}" y="{y+0.75}" width="{s-1.5}" height="{s-1.5}" rx="2" fill="white" stroke="{RULE}" stroke-width="1.5"/>')
def vcell(x, y, kind, s=16):
    if kind == "T":
        add(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="2" fill="{GREEN}"/>')
    else:
        add(f'<rect x="{x+0.75}" y="{y+0.75}" width="{s-1.5}" height="{s-1.5}" rx="2" fill="white" stroke="{GREEN}" stroke-width="1.5"/>')
def miniplot(x, y, w, h, kind, col=INK):
    """p10 (y) against the occupancy covariate x."""
    add(f'<path d="M{x},{y} V{y+h} H{x+w}" fill="none" stroke="{MUTED}" stroke-width="2"/>')
    text(x - 8, y + 10, "p<tspan dy=\'6\' font-size=\'15\'>10</tspan>", 20, MUTED, "end")
    text(x + w, y + h + 28, "x", 20, MUTED, "end", style="italic")
    n = 11
    xs = [x + 14 + i * (w - 28) / (n - 1) for i in range(n)]
    if kind == "flat":
        ys = [y + h * 0.72] * n
    elif kind == "random":
        rnd = random.Random(4)
        ys = [y + h * (0.25 + 0.65 * rnd.random()) for _ in range(n)]
    else:
        ys = [y + h * (0.88 - 0.72 * i / (n - 1)) + random.Random(i).uniform(-6, 6) for i in range(n)]
    for a, b in zip(xs, ys):
        add(f'<circle cx="{a:.1f}" cy="{b:.1f}" r="5.5" fill="{col}"/>')

# ---------------------------------------------------------------- canvas
add(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
add('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
    f'<path d="M0,0 L10,5 L0,10 Z" fill="{MUTED}"/></marker>'
    '<linearGradient id="gx" x1="0" x2="1"><stop offset="0" stop-color="#eef0f2"/><stop offset="1" stop-color="#5d6670"/></linearGradient>'
    '</defs>')
add(f'<rect width="{W}" height="{H}" fill="white"/>')

# ================================================================ (a) one replicate
panel(30, 52, "a")
x0, dx = 150, 110
sites = 8
z      = [1, 1, 1, 0, 1, 0, 0, 0]          # occupancy falls with x (b1 < 0)
conf   = [0, 0, 0, 0, 1, 1, 2, 2]          # soundalikes rise with w (correlated with x)
ver    = [1, 0, 1, 0, 0, 1, 0, 1]          # verified sites
K = 8
rnd = random.Random(11)
y_bird, y_rec, y_det = 120, 205, 300
for i in range(sites):
    cx = x0 + i * dx
    if z[i]:
        bird(cx - 4, y_bird, 1.0, INK)
    for j in range(conf[i]):
        bird(cx + 26 - 30 * j, y_bird - 44 + 20 * j, 0.74, ORANGE, dashed=True)
    recorder(cx, y_rec)
    # automated occasions (column of K cells)
    col = []
    for k in range(K):
        if z[i] and rnd.random() < 0.55:
            col.append("T")
        elif conf[i] and rnd.random() < 0.18 * conf[i] + (0.0 if z[i] else 0.06):
            col.append("F")
        elif not z[i] and rnd.random() < 0.05:
            col.append("F")
        else:
            col.append("0")
    for k, kind in enumerate(col):
        cell(cx - 8, y_det + k * 20, kind)
    if ver[i]:
        headphones(cx, y_det + K * 20 + 22)
        for k in range(3):
            vcell(cx - 8, y_det + K * 20 + 46 + k * 20, "T" if (z[i] and k != 1) else "0")
# covariate bar
yb = y_rec + 52
add(f'<rect x="{x0-40}" y="{yb}" width="{dx*(sites-1)+80}" height="12" rx="6" fill="url(#gx)"/>')
text(x0 - 52, yb + 12, "x", 22, MUTED, "end", style="italic")
# row labels (left margin, minimal)
text(x0 - 52, y_det + 4 * 20 + 6, "classifier", 18, MUTED, "end")
text(x0 - 52, y_det + K * 20 + 86, "listened", 18, MUTED, "end")

# legend for (a): glyph + one word each
lx, ly = 1180, 92
def leg(y, draw, label):
    draw(y); text(lx + 66, y + 7, label, 20, INK)
leg(ly,       lambda y: bird(lx + 26, y + 2, 0.62, INK), "species present (z = 1)")
leg(ly + 46,  lambda y: bird(lx + 26, y + 2, 0.62, ORANGE, dashed=True), "soundalike, rises along x")
leg(ly + 92,  lambda y: cell(lx + 18, y - 6, "T"), "true detection (p<tspan dy='5' font-size='17'>11</tspan>)")
leg(ly + 132, lambda y: cell(lx + 18, y - 6, "F"), "false positive (p<tspan dy='5' font-size='17'>10</tspan>)")
leg(ly + 172, lambda y: headphones(lx + 26, y - 8), "verified clips (certain)")

# models -> target
mx, my = 1120, 330
arrow(1000, my + 40, mx - 6, my + 40)
def model_chip(x, y, kind, label):
    add(f'<rect x="{x}" y="{y}" width="170" height="92" rx="10" fill="white" stroke="{RULE}" stroke-width="2"/>')
    if kind == "flat":
        add(f'<line x1="{x+22}" y1="{y+50}" x2="{x+148}" y2="{y+50}" stroke="{INK}" stroke-width="3.5"/>')
    else:
        add(f'<line x1="{x+22}" y1="{y+72}" x2="{x+148}" y2="{y+26}" stroke="{ORANGE}" stroke-width="3.5"/>')
    text(x + 85, y + 122, label, 19, INK, "middle")
model_chip(mx, my - 6, "flat", "p<tspan dy='5' font-size='17'>10</tspan><tspan dy='-5'> constant</tspan>")
model_chip(mx + 200, my - 6, "slope", "p<tspan dy='5' font-size='17'>10</tspan><tspan dy='-5'> ~ w</tspan>")
text(mx + 85, my + 150, "Stan · occuFP", 16, MUTED, "middle")
text(mx + 285, my + 150, "positive control", 16, MUTED, "middle")
# target: interval coverage of b1
tx = 1640
arrow(mx + 390, my + 40, tx - 14, my + 40)
add(f'<line x1="{tx}" y1="{my+92}" x2="{tx+290}" y2="{my+92}" stroke="{MUTED}" stroke-width="2"/>')
truth = tx + 110
add(f'<line x1="{truth}" y1="{my-22}" x2="{truth}" y2="{my+100}" stroke="{INK}" stroke-width="2" stroke-dasharray="5 4"/>')
text(truth, my + 124, "b<tspan dy='5' font-size='17'>1</tspan>", 21, INK, "middle", style="italic")
for k, (lo, hi, c) in enumerate([(70, 150, BLUE), (55, 140, BLUE), (150, 255, ORANGE), (85, 175, BLUE)]):
    yy = my - 4 + k * 22
    add(f'<line x1="{tx+lo}" y1="{yy}" x2="{tx+hi}" y2="{yy}" stroke="{c}" stroke-width="4" stroke-linecap="round"/>')
    add(f'<circle cx="{tx+(lo+hi)/2}" cy="{yy}" r="5" fill="{c}"/>')
text(tx + 290, my + 150, "coverage, bias", 16, MUTED, "end")
add(f'<line x1="30" y1="605" x2="{W-30}" y2="605" stroke="{RULE}" stroke-width="1.5"/>')

# ================================================================ (b) regimes
panel(30, 660, "b")
by = 710
for i, (kind, roman, col, lab) in enumerate([("flat", "I", INK, "homogeneous"),
                                             ("random", "II", INK, "random"),
                                             ("rise", "III", ORANGE, "confusion")]):
    bx = 110 + i * 250
    miniplot(bx, by, 180, 150, kind, col)
    text(bx + 90, by + 210, roman, 26, INK, "middle", weight="bold")
    text(bx + 90, by + 240, lab, 19, MUTED, "middle")
    if kind == "rise":
        bird(bx + 150, by - 10, 0.7, ORANGE, dashed=True)
    if kind == "random":
        # small die
        add(f'<rect x="{bx+150}" y="{by-22}" width="28" height="28" rx="5" fill="white" stroke="{INK}" stroke-width="2"/>')
        for (ddx, ddy) in [(8, 8), (20, 20), (14, 14)]:
            add(f'<circle cx="{bx+150+ddx}" cy="{by-22+ddy}" r="2.6" fill="{INK}"/>')
# intensity: faint fan of weaker confusion slopes behind regime III
fx, fy, fw, fh = 110 + 2 * 250, by, 180, 150
for f in (0.18, 0.36, 0.55):
    add(f'<line x1="{fx+14}" y1="{fy+fh*0.88:.1f}" x2="{fx+fw-14}" y2="{fy+fh*(0.88-0.72*f):.1f}" '
        f'stroke="{ORANGE}" stroke-width="2" stroke-opacity="0.45" stroke-dasharray="6 4"/>')
text(fx + fw + 6, fy + fh * 0.62, "effect", 16, ORANGE, "start", style="italic")
add(f'<line x1="880" y1="645" x2="880" y2="{H-30}" stroke="{RULE}" stroke-width="1.5"/>')

# ================================================================ (c) design map
panel(910, 660, "c")
cols = [0, 5, 10, 30, 50, 70, 90]
gx0, gdx = 1145, 74
rows = [("I",   "0.05", [0, 5, 10, 30, 50]),
        ("I",   "0.20", [10, 30]),
        ("I",   "0.01", [10, 30]),
        ("II",  "0.05", [10, 30]),
        ("II",  "0.20", [10, 30]),
        ("III", "0.05", [10, 30, 50, 70, 90]),
        ("III", "0.20", [10, 30, 50, 70, 90])]
gy0, gdy = 730, 50
text(1000, gy0 - 34, "regime", 17, MUTED, "middle")
text(1070, gy0 - 34, "p<tspan dy='5' font-size='16'>10</tspan>", 17, MUTED, "middle")
for r, (reg, p, present) in enumerate(rows):
    yy = gy0 + r * gdy
    if r == 0 or rows[r - 1][0] != reg:
        text(1000, yy + 7, reg, 21, INK, "middle", weight="bold")
    text(1070, yy + 7, p, 18, MUTED, "middle")
    for c, v in enumerate(cols):
        xx = gx0 + c * gdx
        if v in present:
            colr = ORANGE if reg == "III" else INK
            add(f'<circle cx="{xx}" cy="{yy}" r="10" fill="{colr}"/>')
            if reg == "III":   # positive control refit on the same data
                add(f'<circle cx="{xx}" cy="{yy}" r="17" fill="none" stroke="{ORANGE}" stroke-width="2"/>')
        else:
            add(f'<circle cx="{xx}" cy="{yy}" r="3" fill="{RULE}"/>')
    if r in (2, 4):
        add(f'<line x1="975" y1="{yy+25}" x2="{gx0+6*gdx+20}" y2="{yy+25}" stroke="{RULE}" stroke-width="1.2"/>')
for c, v in enumerate(cols):
    text(gx0 + c * gdx, gy0 + 7 * gdy + 8, f"{v}", 18, MUTED, "middle")
text(gx0 + 3 * gdx, gy0 + 7 * gdy + 40, "% sites verified", 19, MUTED, "middle")
# intensity block: constant p10, p10 = 0.05, 30% verified
ix0, idx = 1820, 56
eff, cors = [0.25, 0.5, 1.0, 1.5], [0.3, 0.7, 1.0]
add(f'<line x1="{ix0-95}" y1="{gy0-40}" x2="{ix0-95}" y2="{gy0+3*gdy+70}" stroke="{RULE}" stroke-width="1.2"/>')
text(ix0 + idx, gy0 - 34, "intensity", 17, MUTED, "middle")
text(ix0 - 32, gy0 - 34, "effect", 15, MUTED, "end")
for r, e in enumerate(eff):
    yy = gy0 + r * gdy
    text(ix0 - 32, yy + 6, f"{e:g}", 17, MUTED, "end")
    for c, cc in enumerate(cors):
        xx = ix0 + c * idx
        add(f'<rect x="{xx-10}" y="{yy-10}" width="20" height="20" rx="3" fill="{ORANGE}"/>')
for c, cc in enumerate(cors):
    text(ix0 + c * idx, gy0 + 3 * gdy + 38, f"{cc:g}", 17, MUTED, "middle")
text(ix0 + idx, gy0 + 3 * gdy + 68, "cor(w, x)", 17, MUTED, "middle")
text(ix0 + idx, gy0 + 3 * gdy + 98, "p<tspan dy='5' font-size='15'>10</tspan><tspan dy='-5'> 0.05 · 30%</tspan>", 15, MUTED, "middle")
# map legend (glyphs)
ly2 = H - 30
add(f'<circle cx="1010" cy="{ly2}" r="10" fill="{INK}"/>')
text(1030, ly2 + 6, "constant p<tspan dy='5' font-size='16'>10</tspan>", 17, INK)
add(f'<circle cx="1260" cy="{ly2}" r="10" fill="{ORANGE}"/><circle cx="1260" cy="{ly2}" r="17" fill="none" stroke="{ORANGE}" stroke-width="2"/>')
text(1286, ly2 + 6, "+ p<tspan dy='5' font-size='16'>10</tspan><tspan dy='-5'> ~ w (r = 1, 0.7)</tspan>", 17, INK)
add(f'<rect x="{1690-10}" y="{ly2-10}" width="20" height="20" rx="3" fill="{ORANGE}"/>')
text(1710, ly2 + 6, "intensity (constant p<tspan dy='5' font-size='16'>10</tspan><tspan dy='-5'>)</tspan>", 17, INK)

add('</svg>')
open("/home/claude/fig/fig_scheme_v4.svg", "w").write("\n".join(out))
print("written")
