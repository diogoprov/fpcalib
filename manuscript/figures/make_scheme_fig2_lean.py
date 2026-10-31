# Lean version of Figure 2: panel a of make_scheme_fig2_base.py unchanged, and
# panel b widened to the three scenarios, each with one line on what was varied.
# The design map (panels c and d of the full version, kept as
# Fig2_simulation_scheme_full.*) moves to a table.
# Usage, from manuscript/figures/:
#   python3 make_scheme_fig2_lean.py Fig2_simulation_scheme_lean.svg
#   rsvg-convert -w 2060 Fig2_simulation_scheme_lean.svg -o Fig2_simulation_scheme_lean.png
#   rsvg-convert -f pdf Fig2_simulation_scheme_lean.svg -o Fig2_simulation_scheme_lean.pdf
import os, sys

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'make_scheme_fig2_base.py')).read()
head = src[:src.index('# ================================================================ (b) regimes')]
head = head.replace('W, H = 2060, 1250', 'W, H = 2060, 1060')
ns = {'__name__': 'lean'}
exec(head, ns)
add, text, miniplot, bird = ns['add'], ns['text'], ns['miniplot'], ns['bird']
INK, MUTED, ORANGE = ns['INK'], ns['MUTED'], ns['ORANGE']

# ================================================================ (b) scenarios
ns['panel'](30, 660, "b")
by, pw, ph = 700, 230, 150
P10 = "p<tspan dy='5' font-size='15'>10</tspan><tspan dy='-5'>"
G = "γ<tspan dy='5' font-size='15'>FP</tspan><tspan dy='-5'>"
scen = [("flat",   "I",   INK,    "homogeneous",
         [f"{P10} 0.01, 0.05 or 0.20</tspan>", "0–50% of sites verified"]),
        ("random", "II",  INK,    "random among sites",
         [f"Beta-distributed {P10}</tspan>", "10% or 30% of sites verified"]),
        ("rise",   "III", ORANGE, "structured confusion",
         [f"{G} 0.25–1.5, cor(w, x) 0.3–1</tspan>", "10–90% of sites verified"])]
for i, (kind, roman, col, lab, lines) in enumerate(scen):
    bx = 250 + i * 620
    miniplot(bx, by, pw, ph, kind, col)
    text(bx - 120, by + 70, roman, 30, INK, "middle", weight="bold")
    text(bx - 120, by + 100, lab.split()[0] if kind != "random" else "random", 18, MUTED, "middle")
    if kind == "random":
        add(f'<rect x="{bx+pw-30}" y="{by-22}" width="28" height="28" rx="5" fill="white" stroke="{INK}" stroke-width="2"/>')
        for (dx, dy) in [(8, 8), (20, 20), (14, 14)]:
            add(f'<circle cx="{bx+pw-30+dx}" cy="{by-22+dy}" r="2.6" fill="{INK}"/>')
    if kind == "rise":
        bird(bx + pw - 30, by - 10, 0.7, ORANGE, dashed=True)
        for f in (0.18, 0.36, 0.55):
            add(f'<line x1="{bx+14}" y1="{by+ph*0.88:.1f}" x2="{bx+pw-14}" y2="{by+ph*(0.88-0.72*f):.1f}" '
                f'stroke="{ORANGE}" stroke-width="2" stroke-opacity="0.45" stroke-dasharray="6 4"/>')
        text(bx + pw + 8, by + ph * 0.62, "γ<tspan dy='4' font-size='13'>FP</tspan>", 19, ORANGE, "start")
    for k, ln in enumerate(lines):
        text(bx + pw / 2, by + ph + 66 + k * 30, ln, 19, MUTED, "middle")
text(30 + 1000, ns['H'] - 28,
     "every structured-confusion cell also refitted with " + P10 + " ~ w, x or a proxy of w</tspan>",
     18, MUTED, "middle")

add('</svg>')
svg = "\n".join(ns['out']).replace('<svg xmlns=', '<svg xml:space="preserve" xmlns=', 1)
open(sys.argv[1], 'w').write(svg)
print('written', sys.argv[1])
