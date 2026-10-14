# =============================================================================
# fig_dag_v2.R  —  DAG of the false-positive occupancy model (Figure 1)
# Same visual grammar as the hurdle BGLMM DAG (antipredator_v2): priors as
# purple hexagons, parameters as yellow ellipses, observed covariates as blue
# boxes, latent quantities and linear predictors as green ellipses, responses
# as orange double octagons; layers run from priors (top) to data (bottom).
# Priors are those of inst/stan/fp_occupancy_fpcov.stan. W_i (dashed) is the
# optional false-positive covariate; with gamma_FP = 0 the model is the
# constant-rate one.
# Run from the compendium root.
# =============================================================================
library(DiagrammeR)

dag <- DiagrammeR::grViz(paste(readLines(file.path("manuscript", "figures", "fp_dag_v2.dot")),
                               collapse = "\n"))
dag

# export (needs DiagrammeRsvg + rsvg)
svg <- DiagrammeRsvg::export_svg(dag)
rsvg::rsvg_pdf(charToRaw(svg), file.path("manuscript", "figures", "Fig_DAG_model_v2.pdf"))
rsvg::rsvg_png(charToRaw(svg), file.path("manuscript", "figures", "Fig_DAG_model_v2.png"), width = 3600)
