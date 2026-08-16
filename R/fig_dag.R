# =============================================================================
# fig_dag.R  -- DAG of the false-positive occupancy model (DiagrammeR / Graphviz)
# Reproducible: grViz() renders the DOT below; the export block writes the
# publication PDF/PNG. Node conventions: filled grey = observed data;
# bold navy outline = latent state; dashed green = deterministic rate;
# thin outline = parameter with a weakly-informative prior.
# =============================================================================
library(DiagrammeR)

dot <- '
digraph FP_occupancy_DAG {
  graph [rankdir=TB, bgcolor=white, nodesep=0.40, ranksep=0.70, fontname="Helvetica"]
  node  [shape=circle, fixedsize=true, width=0.66, fontname="Helvetica",
         fontsize=13, penwidth=1.3, color="#54627a", fontcolor="#1c2530"]
  edge  [color="#7a8794", arrowsize=0.7, penwidth=1.1]

  /* parameters (weakly-informative priors) */
  beta   [label=<&beta;>]
  fpgap  [label=<&Delta;<sub>fp</sub>>]
  alpha0 [label=<&alpha;<sub>0</sub>>]
  abio   [label=<&alpha;<sub>b</sub>>]
  aaci   [label=<&alpha;<sub>a</sub>>]
  sigu   [label=<&sigma;<sub>u</sub>>]
  delta0 [label=<&delta;<sub>0</sub>>]

  /* deterministic detection rates (global) */
  p10 [label=<p<sub>10</sub>>, style=dashed, color="#2E6E5A"]
  r11 [label=<r<sub>11</sub>>, style=dashed, color="#2E6E5A"]

  subgraph cluster_site {
    label=<<i>site-nights&nbsp;&nbsp;i = 1 &hellip; N</i>>; labelloc=b; labeljust=l;
    fontsize=11; fontcolor="#54627a"; color="#9aa6b2"; style=rounded;
    x [label=<<b>x</b><sub>i</sub>>, style=filled, fillcolor="#dde3e8", color="#1c2530"]
    z [label=<z<sub>i</sub>>, penwidth=2.6, color="#1F3A5F", width=0.72]

    subgraph cluster_auto {
      label=<<i>automated occasions&nbsp;&nbsp;k</i>>; labelloc=b; labeljust=l;
      fontsize=10.5; fontcolor="#54627a"; color="#9aa6b2"; style=rounded;
      p11 [label=<p<sub>11,ik</sub>>, style=dashed, color="#2E6E5A", width=0.84]
      bio [label=<b<sub>ik</sub>>, style=filled, fillcolor="#dde3e8", color="#1c2530", width=0.58]
      aci [label=<a<sub>ik</sub>>, style=filled, fillcolor="#dde3e8", color="#1c2530", width=0.58]
      y2  [label=<y<sup>aut</sup><sub>ik</sub>>, style=filled, fillcolor="#dde3e8", color="#1c2530", width=0.84]
    }
    subgraph cluster_ver {
      label=<<i>verified&nbsp;&nbsp;m</i>>; labelloc=b; labeljust=l;
      fontsize=10.5; fontcolor="#54627a"; color="#9aa6b2"; style=rounded;
      y1 [label=<y<sup>ver</sup><sub>im</sub>>, style=filled, fillcolor="#dde3e8", color="#1c2530", width=0.84]
    }
  }

  subgraph cluster_rec {
    label=<<i>recorders&nbsp;&nbsp;j</i>>; labelloc=b; labeljust=l;
    fontsize=10.5; fontcolor="#54627a"; color="#9aa6b2"; style=rounded;
    uj [label=<u<sub>j</sub>>]
  }

  beta -> z; x -> z
  alpha0 -> p10; fpgap -> p10
  alpha0 -> p11; abio -> p11; aaci -> p11; bio -> p11; aci -> p11
  sigu -> uj; uj -> p11
  delta0 -> r11
  z -> y2; p11 -> y2; p10 -> y2
  z -> y1; r11 -> y1
}
'

g <- grViz(dot)
g   # view in the RStudio Viewer

# ---- export publication files (needs DiagrammeRsvg + rsvg) ----
# library(DiagrammeRsvg); library(rsvg)
# svg <- export_svg(g)
# rsvg_pdf(charToRaw(svg), "Fig_DAG_model.pdf")
# rsvg_png(charToRaw(svg), "Fig_DAG_model.png", width = 2600)
