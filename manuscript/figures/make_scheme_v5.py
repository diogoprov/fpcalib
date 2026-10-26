# Builds Fig1_simulation_scheme_v5.svg from v4: marks the revision refits in
# panel c and adds panel d, the observation-confirmation runs (08 and 10).
# Usage, from manuscript/figures/:
#   python3 make_scheme_v5.py Fig1_simulation_scheme_v4.svg Fig1_simulation_scheme_v5.svg
#   rsvg-convert -w 2060 Fig1_simulation_scheme_v5.svg -o Fig1_simulation_scheme_v5.png
#   rsvg-convert -f pdf Fig1_simulation_scheme_v5.svg -o Fig1_simulation_scheme_v5.pdf
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
# regime I (rows y = 730, 780, 830): + p10 ~ x on every simulated cell
cols = [1145, 1219, 1293, 1367, 1441, 1515, 1589]
reg1 = {730: cols[:5], 780: cols[2:4], 830: cols[2:4]}
for y, xs in reg1.items():
    for x in xs:
        add += ring(x, y, BLUE)
# regime II (rows y = 880, 930), 10% and 30%: + site random effect on p10
for y in (880, 930):
    for x in cols[2:4]:
        add += ring(x, y, DARK, dash='4 4')

# --- panel d: observation confirmation ----------------------------------------
add += f'<line x1="30" y1="965" x2="850" y2="965" stroke="{LIGHT}" stroke-width="1.5"/>\n'
add += text(30, 1010, 'd', size=42, fill=DARK, anchor='start', weight='bold')
add += text(80, 1006, 'observation confirmation: no verified sites, a share of occasions checked',
            size=23, fill=DARK, anchor='start')
add += text(190, 1052, 'effect', anchor='end')
add += text(190, 1092, P10 + "<tspan dy='-5'> 0.05</tspan>", anchor='end')
add += text(190, 1142, P10 + "<tspan dy='-5'> 0.20</tspan>", anchor='end')
groups = [(0, 235), (0.5, 395), (1, 555), (1.5, 715)]   # effect, x of the 5% column
offs = [(5, 0), (10, 46), (30, 92)]
for eff, x0 in groups:
    add += text(x0 + 46, 1052, f'{eff:g}' if eff else '0 (I)')
    for y in (1085, 1135):
        for pct, dx in offs:
            x = x0 + dx
            if eff == 0 and pct != 10:
                add += dot(x, y, LIGHT, r=3)
                continue
            add += dot(x, y, DARK if eff == 0 else ORANGE)
            add += ring(x, y, BLUE, r=15)
            if eff == 1.5:
                add += ring(x, y, ORANGE, r=21)
    for pct, dx in offs:
        add += text(x0 + dx, 1185, str(pct), size=20)
add += text(490, 1215, '% automated occasions checked · cor(w, x) = 0.7', size=22)

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
