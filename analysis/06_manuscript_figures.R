# =============================================================================
# SUPERSEDED (0.3.0): Figures 5 and 6 of the manuscript are now drawn by
# 14_figs_3_5_6.R from the same summaries. Kept for the record.
# 06_manuscript_figures.R
# -----------------------------------------------------------------------------
# Figures 6 and 7 of the manuscript, drawn from the scored summaries only (no
# Stan fits). Run from the compendium root after 01, 03, 04, and 05, or straight
# away with the .rds files under version control.
#
#   Figure 6  coverage of the 95% CrI of b1 against the fraction of sites
#             verified, under structured confusion, for four models:
#             constant p10 (01), p10 ~ x (03), p10 ~ proxy of w and p10 ~ w (04),
#             plus p10 ~ x when cor(w, x) = 1 (03, star).
#   Figure 7  bias and coverage of b1 under the constant-p10 model across the
#             intensity grid (05), with +/- 2 Monte Carlo standard errors.
#
# Writes manuscript/figures/fig6_recovery_4arms.{pdf,png} and
#        manuscript/figures/fig7_confusion_intensity.{pdf,png}.
# =============================================================================

library(ggplot2)

summ_main <- readRDS(file.path("data", "fp_sim_summary.rds"))
summ_fix  <- readRDS(file.path("data", "fp_fix_summary.rds"))
summ_pc   <- readRDS(file.path("data", "fp_positive_control_summary.rds"))
summ_int  <- readRDS(file.path("data", "fp_intensity_summary.rds"))

# shared look --------------------------------------------------------------------
pal <- c("Constant"   = "#7A7A7A",
         "Proxy of w" = "#C8641E",
         "x"          = "#2E9E6E",
         "w"          = "#2A6EBB")
shp <- c("Constant" = 16, "Proxy of w" = 17, "x" = 15, "w" = 18)
lab <- c("Constant"   = "Constant~p[10]",
         "Proxy of w" = "p[10] %~% proxy~of~w~(r == 0.7)",
         "x"          = "p[10] %~% x~(occupancy~covariate)",
         "w"          = "p[10] %~% w~(true~gradient)")
p10_lab <- function(p) sprintf("p[10] == '%.2f'", p)

theme_fp <- function(base_size = 12) {
  theme_classic(base_size = base_size) +
    theme(panel.grid.major = element_line(colour = "grey92", linewidth = 0.4),
          strip.background = element_blank(),
          strip.text = element_text(size = base_size + 2),
          legend.position = "bottom")
}

# Figure 6 -----------------------------------------------------------------------
is_conf <- function(d) d$conf_effect == 1.5 & d$conf_cor == 0.7

fig6_dat <- list(
  Constant     = subset(summ_main, is_conf(summ_main),
                        c(p10, coverage, cov95 = stan_b1_coverage95)),
  x            = subset(summ_fix, is_conf(summ_fix),
                        c(p10, coverage, cov95 = fixstan_b1_coverage95)),
  `Proxy of w` = subset(summ_pc, proxy_cor == 0.7,
                        c(p10, coverage, cov95 = fpcov_b1_cov95)),
  w            = subset(summ_pc, proxy_cor == 1,
                        c(p10, coverage, cov95 = fpcov_b1_cov95))
) |>
  purrr::imap(function(d, m) {
    d <- as.data.frame(d)
    names(d) <- c("p10", "coverage", "cov95")
    transform(d, model = m)
  }) |>
  purrr::list_rbind() |>
  transform(model = factor(model, levels = names(pal)),
            panel = p10_lab(p10))

fig6_star <- subset(as.data.frame(summ_fix), conf_cor == 1,
                    c(p10, coverage, fixstan_b1_coverage95)) |>
  transform(panel = p10_lab(p10))
names(fig6_star)[3] <- "cov95"

fig6 <- ggplot(fig6_dat, aes(coverage, cov95, colour = model, shape = model)) +
  geom_hline(yintercept = 0.95, linetype = 2, colour = "grey55") +
  geom_line(linewidth = 1.1) +
  geom_point(size = 3.2) +
  geom_point(data = fig6_star, aes(coverage, cov95), inherit.aes = FALSE,
             shape = 8, size = 4.5, stroke = 1.3, colour = pal[["x"]]) +
  facet_wrap(~ panel, labeller = label_parsed) +
  scale_colour_manual(values = pal, labels = scales::parse_format()(lab), name = NULL) +
  scale_shape_manual(values = shp, labels = scales::parse_format()(lab), name = NULL) +
  scale_x_continuous(breaks = c(0.1, 0.3, 0.5, 0.7, 0.9),
                     labels = scales::percent) +
  scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  labs(x = "Sites verified",
       y = expression("Coverage of the 95% CrI for " * b[1]),
       caption = expression("Asterisk: " * p[10] %~% x * " when cor(w, x) = 1")) +
  guides(colour = guide_legend(nrow = 2), shape = guide_legend(nrow = 2)) +
  theme_fp()

ggsave(file.path("manuscript", "figures", "fig6_recovery_4arms.pdf"),
       fig6, width = 9, height = 4.6)
ggsave(file.path("manuscript", "figures", "fig6_recovery_4arms.png"),
       fig6, width = 9, height = 4.6, dpi = 300)

# Figure 7 -----------------------------------------------------------------------
cor_pal <- c("0.3" = "#9BB8D9", "0.7" = "#2A6EBB", "1" = "#12355B")
cor_shp <- c("0.3" = 16, "0.7" = 17, "1" = 15)

int <- as.data.frame(summ_int)
fig7_dat <- purrr::list_rbind(list(
  data.frame(conf_effect = int$conf_effect, conf_cor = int$conf_cor,
             metric = "Bias", value = int$stan_b1_bias,
             lo = NA_real_, hi = NA_real_),
  data.frame(conf_effect = int$conf_effect, conf_cor = int$conf_cor,
             metric = "Coverage", value = int$stan_b1_coverage95,
             lo = pmax(0, int$stan_b1_coverage95 - 2 * int$b1_cov_mcse),
             hi = pmin(1, int$stan_b1_coverage95 + 2 * int$b1_cov_mcse))
)) |>
  transform(conf_cor = factor(conf_cor),
            metric = factor(metric, levels = c("Bias", "Coverage"),
                            labels = c("Bias~of~b[1]",
                                       "Coverage~of~the~'95%'~CrI~of~b[1]")))
refs <- data.frame(metric = levels(fig7_dat$metric), ref = c(0, 0.95))
refs$metric <- factor(refs$metric, levels = levels(fig7_dat$metric))

fig7 <- ggplot(fig7_dat, aes(conf_effect, value, colour = conf_cor, shape = conf_cor)) +
  geom_hline(data = refs, aes(yintercept = ref), linetype = 2, colour = "grey55") +
  geom_linerange(aes(ymin = lo, ymax = hi), linewidth = 0.6, na.rm = TRUE,
                 position = position_dodge(width = 0.06), show.legend = FALSE) +
  geom_line(linewidth = 1.1, position = position_dodge(width = 0.06)) +
  geom_point(size = 3, position = position_dodge(width = 0.06)) +
  facet_wrap(~ metric, scales = "free_y", labeller = label_parsed) +
  scale_colour_manual(values = cor_pal, name = "cor(w, x)") +
  scale_shape_manual(values = cor_shp, name = "cor(w, x)") +
  scale_x_continuous(breaks = c(0.25, 0.5, 1, 1.5)) +
  labs(x = expression("Effect of the confusing gradient w on logit(" * p[10] * ")"),
       y = NULL) +
  theme_fp()

ggsave(file.path("manuscript", "figures", "fig7_confusion_intensity.pdf"),
       fig7, width = 9, height = 4.2)
ggsave(file.path("manuscript", "figures", "fig7_confusion_intensity.png"),
       fig7, width = 9, height = 4.2, dpi = 300)

message("Figures 6 and 7 written to manuscript/figures/")
