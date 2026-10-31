# =============================================================================
# 13_fig4_caterpillars.R
# Figure 4 of the manuscript: per-replicate 95% credible intervals of the
# constant-rate Bayesian model, homogeneous baseline vs heterogeneous regime.
# Merges the former p10 (unstructured) and b1 (structured) caterpillar figures.
# (a, b) p10 at p10 = 0.05 and 30% of sites verified; (c, d) b1 at p10 = 0.20
# and 10% of sites verified. The structured cell has 300 replicates; the first
# 100 are drawn so that every panel shows 100.
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(tidyverse)
library(patchwork)

source("R/fp_sim_pilot.R")
source("R/figs_didaticas_curiango.R")

res <- add_scenario(readRDS(file.path("data", "fp_sim_results.rds"))) |>
  filter(stan_ok, rep <= 100)

pal <- c(`TRUE` = "#2a78d6", `FALSE` = "#e34948")

caterpillar <- function(d, param, truth_col, title, xlab) {
  d <- d |>
    transmute(est = .data[[paste0("stan_", param, "_est")]],
              lo = .data[[paste0("stan_", param, "_lo")]],
              hi = .data[[paste0("stan_", param, "_hi")]],
              truth = .data[[truth_col]]) |>
    arrange(est) |>
    mutate(rank = row_number(),
           caught = factor(lo <= truth & hi >= truth, c("TRUE", "FALSE")))
  lab <- sprintf("Coverage = %.0f%%", 100 * mean(d$caught == "TRUE"))
  ggplot(d, aes(y = rank)) +
    geom_vline(xintercept = mean(d$truth), linetype = "dashed", linewidth = 0.4,
               colour = "#2b2a28") +
    geom_linerange(aes(xmin = lo, xmax = hi, colour = caught), linewidth = 0.35) +
    geom_point(aes(x = est, colour = caught), size = 0.5) +
    scale_colour_manual(values = pal, name = NULL,
                        labels = c(`TRUE` = "95% interval contains the truth",
                                   `FALSE` = "95% interval misses the truth"),
                        breaks = c("TRUE", "FALSE"), drop = FALSE) +
    labs(title = title, subtitle = lab, x = xlab, y = NULL)
}

cell_p10 <- \(s) filter(res, scenario == s, true_p10 == 0.05, verified_coverage == 0.3)
cell_b1  <- \(s) filter(res, scenario == s, true_p10 == 0.20, verified_coverage == 0.1)
xp10 <- expression("False-positive rate" ~ italic(p)[10])
xb1  <- expression("Environmental effect" ~ beta[1])

pa <- caterpillar(cell_p10("base"), "p10", "true_p10_marginal",
                  "Homogeneous false positives", xp10)
pb <- caterpillar(cell_p10("Beta (nao estruturada)"), "p10", "true_p10_marginal",
                  "Unstructured heterogeneity", xp10)
pc <- caterpillar(cell_b1("base"), "b1", "true_b1",
                  "Homogeneous false positives", xb1)
pd <- caterpillar(cell_b1("confusao (estruturada)"), "b1", "true_b1",
                  "Structured confusion", xb1)

# shared x range within each row, so the shift away from the truth reads directly
row_x <- \(p, q) {
  r <- range(c(layer_scales(p)$x$range$range, layer_scales(q)$x$range$range))
  list(p + coord_cartesian(xlim = r), q + coord_cartesian(xlim = r))
}
# one legend: panels without covering intervals would draw a second key
no_key <- guides(colour = "none")
top <- row_x(pa, pb + no_key); bot <- row_x(pc + no_key, pd + no_key)

fig <- (top[[1]] + top[[2]] + bot[[1]] + bot[[2]]) +
  plot_layout(ncol = 2, guides = "collect") +
  plot_annotation(tag_levels = "a") &
  theme_minimal(base_size = 9) &
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        panel.grid.major.y = element_blank(), axis.text.y = element_blank(),
        plot.title = element_text(size = 9, face = "bold"),
        plot.tag = element_text(face = "bold"))

ggsave("manuscript/figures/Fig4_caterpillars.png", fig, width = 7, height = 6,
       dpi = 300, bg = "white")
ggsave("manuscript/figures/Fig4_caterpillars.pdf", fig, width = 7, height = 6)
message("Figure 4 written to manuscript/figures/")
