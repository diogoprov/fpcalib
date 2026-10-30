# =============================================================================
# 14_figs_3_5_6.R
# Figures 3, 5 and 6 of the manuscript, redrawn in the style of Figures 4 and 7
# from the scored summaries only (no Stan fits).
#   Figure 3  coverage of the constant-rate Bayesian model and occuFP in the
#             three false-positive regimes; the four cells shared by all regimes
#             (p10 = 0.05, 0.20 x 10%, 30% of sites verified).
#   Figure 5  coverage of b1 against the share of sites verified under
#             structured confusion, four models (replaces 06, Figure 6).
#   Figure 6  bias and coverage of b1 across the intensity grid (replaces 06,
#             Figure 7), coverage with +/- 2 Monte Carlo standard errors.
# Heights match the frames of the figures in the manuscript .docx.
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(tidyverse)
library(patchwork)

summ_main <- readRDS(file.path("data", "fp_sim_summary.rds"))
summ_fix  <- readRDS(file.path("data", "fp_fix_summary.rds"))
summ_pc   <- readRDS(file.path("data", "fp_positive_control_summary.rds"))
summ_int  <- readRDS(file.path("data", "fp_intensity_summary.rds"))

theme_set(theme_minimal(base_size = 10) +
            theme(panel.grid.minor = element_blank(), legend.position = "top",
                  strip.text = element_text(face = "bold"),
                  plot.title = element_text(size = 10, face = "bold")))
ink <- "#52514e"
save_fig <- function(p, name, height) {
  ggsave(file.path("manuscript", "figures", paste0(name, ".png")), p,
         width = 7, height = height, dpi = 300, bg = "white")
  ggsave(file.path("manuscript", "figures", paste0(name, ".pdf")), p,
         width = 7, height = height)
}

# Figure 3 -----------------------------------------------------------------------
fw_cols <- c("Bayesian model (crywolf)" = "#52514e", "occuFP (unmarked)" = "#eb6834")
fw_shp  <- c("Bayesian model (crywolf)" = 16, "occuFP (unmarked)" = 17)
regimes <- c("Homogeneous", "Unstructured", "Structured confusion")

f3 <- summ_main |>
  filter(p10 %in% c(0.05, 0.20), coverage %in% c(0.1, 0.3)) |>
  mutate(regime = case_when(conf_effect > 0 ~ regimes[3],
                            beta_conc > 0 ~ regimes[2], TRUE ~ regimes[1])) |>
  transmute(regime, p10_stan = stan_p10_coverage95, p10_occufp = occufp_p10_coverage95,
            b1_stan = stan_b1_coverage95, b1_occufp = occufp_b1_coverage95) |>
  pivot_longer(-regime, names_to = c("param", "fw"), names_sep = "_") |>
  mutate(fw = if_else(fw == "stan", names(fw_cols)[1], names(fw_cols)[2]),
         regime = factor(regime, rev(regimes)),
         param = factor(param, c("p10", "b1"),
                        c("False*'-'*positive~rate~italic(p)[10]",
                          "Environmental~effect~italic(b)[1]")))
# means labelled beyond the spread of their cells, rounding half up (0.945 -> 0.95)
f3_mean <- f3 |>
  summarise(lab_x = if_else(mean(value) > 0.5, min(value) - 0.03, max(value) + 0.03),
            value = mean(value), .by = c(regime, param, fw)) |>
  mutate(label = sprintf("%.2f", round(value + 1e-9, 2)),
         hjust = if_else(value > 0.5, 1, 0))
dodge3 <- position_dodge(width = 0.45)

fig3 <- ggplot(f3, aes(value, regime, colour = fw, shape = fw)) +
  geom_vline(xintercept = 0.95, linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_point(position = dodge3, size = 1.2, alpha = 0.45) +
  geom_point(data = f3_mean, position = dodge3, size = 3) +
  geom_text(data = f3_mean, aes(x = lab_x, label = label, hjust = hjust),
            position = dodge3, size = 3, colour = ink, show.legend = FALSE) +
  facet_wrap(~param, labeller = label_parsed) +
  scale_colour_manual(values = fw_cols, name = NULL) +
  scale_shape_manual(values = fw_shp, name = NULL) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  labs(x = "Coverage of the 95% interval", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.spacing.x = unit(1.5, "lines"))
save_fig(fig3, "Fig3_coverage_regimes", 3.125)

# Figure 5 -----------------------------------------------------------------------
mod_cols <- c("Constant" = "#8c8b87", "Proxy of w" = "#eda100",
              "x" = "#2a78d6", "w" = "#1baf7a")
mod_shp  <- c("Constant" = 16, "Proxy of w" = 17, "x" = 15, "w" = 18)
mod_lab  <- c("Constant" = "Constant~italic(p)[10]",
              "Proxy of w" = "italic(p)[10] %~% proxy~of~italic(w)~(r == 0.7)",
              "x" = "italic(p)[10] %~% italic(x)~(occupancy~covariate)",
              "w" = "italic(p)[10] %~% italic(w)~(confusing~gradient)")
p10_lab <- \(p) sprintf("italic(p)[10] == '%.2f'", p)
is_conf <- \(d) d$conf_effect == 1.5 & d$conf_cor == 0.7

f5 <- bind_rows(
  Constant = filter(summ_main, is_conf(summ_main)) |>
    select(p10, coverage, cov95 = stan_b1_coverage95),
  x = filter(summ_fix, is_conf(summ_fix)) |>
    select(p10, coverage, cov95 = fixstan_b1_coverage95),
  `Proxy of w` = filter(summ_pc, proxy_cor == 0.7) |>
    select(p10, coverage, cov95 = fpcov_b1_cov95),
  w = filter(summ_pc, proxy_cor == 1) |>
    select(p10, coverage, cov95 = fpcov_b1_cov95),
  .id = "model") |>
  mutate(model = factor(model, names(mod_cols)), panel = p10_lab(p10))
f5_star <- filter(summ_fix, conf_cor == 1) |>
  transmute(coverage, cov95 = fixstan_b1_coverage95, panel = p10_lab(p10))

fig5 <- ggplot(f5, aes(coverage, cov95, colour = model, shape = model)) +
  geom_hline(yintercept = 0.95, linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_line(linewidth = 0.7) +
  geom_point(size = 2.4) +
  geom_point(data = f5_star, aes(coverage, cov95), inherit.aes = FALSE,
             shape = 8, size = 3, stroke = 0.9, colour = mod_cols[["x"]]) +
  facet_wrap(~panel, labeller = label_parsed) +
  scale_colour_manual(values = mod_cols, labels = scales::label_parse()(mod_lab),
                      name = NULL) +
  scale_shape_manual(values = mod_shp, labels = scales::label_parse()(mod_lab),
                     name = NULL) +
  scale_x_continuous(breaks = c(0.1, 0.3, 0.5, 0.7, 0.9), labels = scales::percent) +
  scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  labs(x = "Sites verified", y = expression("Coverage of the 95% CrI of" ~ italic(b)[1]),
       caption = expression("Asterisk:" ~ italic(p)[10] %~% italic(x) ~
                              "when cor(" * italic(w) * "," ~ italic(x) * ") = 1")) +
  guides(colour = guide_legend(nrow = 2), shape = guide_legend(nrow = 2))
save_fig(fig5, "Fig5_verification_models", 3.03)

# Figure 6 -----------------------------------------------------------------------
cor_cols <- c("0.3" = "#b9b0ee", "0.7" = "#6250d6", "1" = "#2f2475")
cor_shp  <- c("0.3" = 16, "0.7" = 17, "1" = 15)
dodge6 <- position_dodge(width = 0.06)

f6 <- summ_int |>
  transmute(conf_effect, conf_cor = factor(conf_cor), bias = stan_b1_bias,
            cov = stan_b1_coverage95,
            lo = pmax(0, cov - 2 * b1_cov_mcse), hi = pmin(1, cov + 2 * b1_cov_mcse))
cor_scales <- list(
  scale_colour_manual(values = cor_cols, name = expression("cor(" * italic(w) * "," ~ italic(x) * ")")),
  scale_shape_manual(values = cor_shp, name = expression("cor(" * italic(w) * "," ~ italic(x) * ")")),
  scale_x_continuous(breaks = c(0.25, 0.5, 1, 1.5)))
xlab6 <- expression("Effect of the confusing gradient" ~ italic(w) ~ "on logit(" * italic(p)[10] * ")")

p6a <- ggplot(f6, aes(conf_effect, bias, colour = conf_cor, shape = conf_cor)) +
  geom_hline(yintercept = 0, linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_line(linewidth = 0.7, position = dodge6) +
  geom_point(size = 2.4, position = dodge6) +
  cor_scales + labs(x = NULL, y = expression("Bias of" ~ italic(b)[1]), tag = "a")
p6b <- ggplot(f6, aes(conf_effect, cov, colour = conf_cor, shape = conf_cor)) +
  geom_hline(yintercept = 0.95, linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_linerange(aes(ymin = lo, ymax = hi), linewidth = 0.5, position = dodge6,
                 show.legend = FALSE) +
  geom_line(linewidth = 0.7, position = dodge6) +
  geom_point(size = 2.4, position = dodge6) +
  cor_scales + scale_y_continuous(limits = c(0, 1)) +
  labs(x = NULL, y = expression("Coverage of the 95% CrI of" ~ italic(b)[1]), tag = "b")

fig6 <- (p6a + p6b) / wrap_elements(grid::textGrob(xlab6, gp = grid::gpar(fontsize = 10))) +
  plot_layout(heights = c(1, 0.06), guides = "collect") &
  theme(legend.position = "top", plot.tag = element_text(face = "bold"))
save_fig(fig6, "Fig6_confusion_intensity", 3.5)

message("Figures 3, 5 and 6 written to manuscript/figures/")
