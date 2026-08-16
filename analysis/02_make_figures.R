# =============================================================================
# 02_make_figures.R
# Regenerate the coverage figures from the saved results (no rerun needed).
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(dplyr); library(tidyr); library(ggplot2)

source("R/fp_sim_pilot.R")
source("R/figs_didaticas_curiango.R")

res <- readRDS(file.path("data", "fp_sim_100reps_results.rds"))
dir.create("analysis/figures", showWarnings = FALSE)

# --- (a) coverage caterpillars: per-replicate intervals vs the truth line ----
p_b1 <- plot_coverage_caterpillar(res, "b1",
          scenarios = c("base", "confusao (estruturada)"))
ggsave("analysis/figures/fig_coverage_b1.pdf", p_b1, width = 10, height = 6)

p_p10 <- plot_coverage_caterpillar(res, "p10",
           scenarios = c("base", "Beta (nao estruturada)"))
ggsave("analysis/figures/fig_coverage_p10.pdf", p_p10, width = 10, height = 6)

# --- (b) coverage summary: Stan FP model vs occuFP, both parameters ----------
s <- summarise_pilot(res) |>
  mutate(arm = case_when(conf_effect != 0 ~ "structured confusion",
                         beta_conc  != 0 ~ "unstructured (Beta)",
                         TRUE            ~ "homogeneous")) |>
  select(arm, stan_p10_coverage95, stan_b1_coverage95,
         occufp_p10_coverage95, occufp_b1_coverage95) |>
  pivot_longer(-arm, names_to = "key", values_to = "coverage") |>
  separate(key, into = c("model", "param", NA), sep = "_", extra = "drop") |>
  group_by(arm, model, param) |>
  summarise(coverage = mean(coverage, na.rm = TRUE), .groups = "drop") |>
  mutate(arm = factor(arm, levels = c("structured confusion",
                                      "unstructured (Beta)", "homogeneous")),
         model = recode(model, stan = "Stan FP model", occufp = "occuFP"))

p_sum <- ggplot(s, aes(coverage, arm, colour = model)) +
  geom_vline(xintercept = 0.95, linetype = "dashed", colour = "grey60") +
  geom_point(size = 3, position = position_dodge(width = 0.4)) +
  facet_wrap(~param) + xlim(0, 1) +
  labs(x = "95% interval coverage", y = NULL, colour = NULL,
       title = "Interval coverage: Stan FP model vs occuFP") +
  theme_bw(base_size = 12) + theme(legend.position = "bottom")
ggsave("analysis/figures/fig_coverage_summary.pdf", p_sum, width = 10, height = 5)

message("figures written to analysis/figures/")
