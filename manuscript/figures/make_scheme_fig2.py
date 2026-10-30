# Builds Figure 2 of the manuscript (Fig2_simulation_scheme) from the panels a-c
# of make_scheme_fig2_base.py: marks the revision refits in panel c, the two cells
# in which w = x, and adds panel d, the observation-confirmation runs (08, 10 and 11).
# From make_scheme_v6.py. Usage, from manuscript/figures/:
#   python3 make_scheme_fig2_base.py Fig2_simulation_scheme_base.svg
#   python3 make_scheme_fig2.py Fig2_simulation_scheme_base.svg Fig2_simulation_scheme.svg
#   rsvg-convert -w 2060 Fig2_simulation_scheme.svg -o Fig2_simulation_scheme.png
#   rsvg-convert -f pdf Fig2_simulation_scheme.svg -o Fig2_simulation_scheme.pdf
import re, sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
s = re.sub(r'<metadata>.*?</metadata>', '', s, flags=re.S)

FONT = 'font-family="Helvetica, Arial, FreeSans, sans-serif"'
DARK, GREY, LIGHT, ORANGE, BLUE = '#2b2b2b', '#6b6b6b', '#d9d9d9', '#C8691C', '#2A6FB0'
H_OLD, H_NEW = 1250, 1300

def text(x, y, t, size=23, fill=GREY, anchor='middle', weight='normal', style='normal'):
    return (f'<text x="{x}" y="{y}" {FONT} font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
            f'font-weight="{weight}" font-style="{style}">{t}</text>\n')

def dot(x, y, fill, r=10):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"/>\n'

def ring(x, y, colour, r=17, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="{colour}" stroke-width="2"{d}/>\n'

P10 = "p<tspan dy='5' font-size='16'>10</tspan>"

# taller canvas for a second legend row
s = s.replace(f'width="2060" height="{H_OLD}" viewBox="0 0 2060 {H_OLD}"',
              f'width="2060" height="{H_NEW}" viewBox="0 0 2060 {H_NEW}" xml:space="preserve"', 1)
s = s.replace(f'<rect width="2060" height="{H_OLD}" fill="white"/>',
              f'<rect width="2060" height="{H_NEW}" fill="white"/>', 1)
assert f'height="{H_NEW}"' in s

add = ''
# --- panel c: revision refits on cells of the main run ------------------------
# regime I (rows y = 730, 780, 830, p10 0.01, 0.05, 0.20): + p10 ~ x on every simulated cell
cols = [1145, 1219, 1293, 1367, 1441, 1515, 1589]
reg1 = {730: cols[2:4], 780: cols[:5], 830: cols[2:4]}
for y, xs in reg1.items():
    for x in xs:
        add += ring(x, y, BLUE)
# regime II (rows y = 880, 930), 10% and 30%: + site random effect on p10
for y in (880, 930):
    for x in cols[2:4]:
        add += ring(x, y, DARK, dash='4 4')
# regime III (rows y = 980, 1030): two more cells at 30% in which w = x,
# fitted with the constant rate and with p10 ~ x (star, as in Figure 6)
def star(cx, cy, r=9, fill=ORANGE):
    import math
    pts = ' '.join(f'{cx + (r if k % 2 == 0 else r * 0.45) * math.sin(math.pi * k / 5):.1f},'
                   f'{cy - (r if k % 2 == 0 else r * 0.45) * math.cos(math.pi * k / 5):.1f}' for k in range(10))
    return f'<polygon points="{pts}" fill="{fill}"/>\n'
for y in (980, 1030):
    add += star(cols[3] + 33, y - 15)
add += star(1652, 1108) + text(1668, 1115, 'w = x, 30% verified', size=21, fill=DARK, anchor='start')

# --- panel d: observation confirmation ----------------------------------------
add += f'<line x1="30" y1="965" x2="850" y2="965" stroke="{LIGHT}" stroke-width="1.5"/>\n'
add += text(30, 1010, 'd', size=42, fill=DARK, anchor='start', weight='bold')
add += text(80, 1006, 'observation confirmation: no verified sites, a share of occasions checked',
            size=23, fill=DARK, anchor='start')
add += text(30, 1052, 'cor(w, x)', anchor='start')
add += text(200, 1052, 'effect', anchor='end')
rows = [(0.7, 0.05, 1084), (0.7, 0.20, 1128), (1.0, 0.05, 1180), (1.0, 0.20, 1224)]
for cor, p10, y in rows:
    add += text(200, y + 7, P10 + f"<tspan dy='-5'> {p10:.2f}</tspan>", anchor='end', size=21)
add += text(108, 1113, '0.7', size=21)
add += text(108, 1209, '1.0', size=21)
add += f'<line x1="70" y1="1152" x2="830" y2="1152" stroke="{LIGHT}" stroke-width="1.2"/>\n'
groups = [(0, 235), (0.5, 395), (1, 555), (1.5, 715)]   # effect, x of the 5% column
offs = [(5, 0), (10, 46), (30, 92)]
for eff, x0 in groups:
    add += text(x0 + 46, 1052, f'{eff:g}' if eff else '0 (I)')
    for cor, p10, y in rows:
        for pct, dx in offs:
            x = x0 + dx
            if eff == 0 and (pct != 10 or cor == 1.0):
                add += dot(x, y, LIGHT, r=3)
                continue
            add += dot(x, y, DARK if eff == 0 else ORANGE)
            add += ring(x, y, BLUE, r=15)
            if eff == 1.5 and cor == 0.7:
                add += ring(x, y, ORANGE, r=21)
    for pct, dx in offs:
        add += text(x0 + dx, 1262, str(pct), size=20)
add += text(490, 1290, '% automated occasions checked', size=22)
add += text(30, 1290, '0 (I): no w', size=20, anchor='start')

# --- second legend row ----------------------------------------------------------
add += dot(1010, 1270, '#ffffff', r=1) + ring(1010, 1270, BLUE)
add += text(1036, 1276, '+ ' + P10 + "<tspan dy='-5'> ~ x</tspan>", fill=DARK, anchor='start')
add += ring(1260, 1270, DARK, dash='4 4')
add += text(1286, 1276, '+ site random effect on ' + P10, fill=DARK, anchor='start')
add += ring(1680, 1270, ORANGE, r=23) + ring(1680, 1270, BLUE, r=17) + dot(1680, 1270, ORANGE)
add += text(1712, 1276, 'd: + ' + P10 + "<tspan dy='-5'> ~ w</tspan>", fill=DARK, anchor='start')

s = s.replace('</svg>', add + '</svg>')
open(dst, 'w').write(s)
print('written', dst)
