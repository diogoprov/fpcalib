# =============================================================================
# 16_fig7_nightjar.R
# Figure 7 of the manuscript: the nightjar example by classifier threshold,
# from the fits of 15_nightjar.R (data/nightjar_fits.rds).
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(tidyverse)
library(patchwork)

nj <- readRDS(file.path("data", "nightjar_fits.rds"))
est <- map_dfr(nj$fits, \(f) mutate(f$table, fp = f$fp, threshold = f$threshold)) |>
  mutate(model = if_else(fp == "~ 1", "Constant false-positive rate",
                         "False-positive rate ~ temperature + humidity"))
pal <- c("Constant false-positive rate" = "#8c8b87",
         "False-positive rate ~ temperature + humidity" = "#2a78d6")
dodge <- position_dodge(width = 0.09)

effects <- est |>
  filter(variable %in% c("occ_temp", "occ_rh", "occ_moon")) |>
  mutate(variable = factor(variable, c("occ_temp", "occ_rh", "occ_moon"),
                           c("Temperature", "Relative humidity", "Moonlight")))
pa <- ggplot(effects, aes(threshold, mean, colour = model)) +
  geom_hline(yintercept = 0, linewidth = 0.3, colour = "#52514e") +
  geom_pointrange(aes(ymin = lower, ymax = upper), position = dodge, size = 0.3, linewidth = 0.6) +
  facet_wrap(~variable, nrow = 1) +
  scale_x_continuous(breaks = c(0.2, 0.4, 0.6, 0.8)) +
  scale_colour_manual(values = pal, name = NULL) +
  labs(x = "Classifier threshold", y = "Effect on nightly use (logit scale)", tag = "a")
pb <- est |>
  filter(variable == "p10_bar") |>
  ggplot(aes(threshold, 100 * mean, colour = model)) +
  geom_pointrange(aes(ymin = 100 * lower, ymax = 100 * upper), position = dodge, size = 0.3, linewidth = 0.6) +
  scale_x_continuous(breaks = c(0.2, 0.4, 0.6, 0.8)) +
  scale_y_log10(breaks = c(0.05, 0.1, 0.3, 1, 3), labels = c("0.05", "0.1", "0.3", "1", "3")) +
  scale_colour_manual(values = pal, guide = "none") +
  labs(x = "Classifier threshold", y = "False-positive rate per recording (%)", tag = "b")

fig7 <- (pa + pb + plot_layout(widths = c(3, 1.1))) &
  theme_minimal(base_size = 10) &
  theme(legend.position = "top", panel.grid.minor = element_blank(),
        plot.tag = element_text(face = "bold"))
fig7 <- fig7 + plot_layout(guides = "collect") & theme(legend.position = "top")
ggsave(file.path("manuscript", "figures", "Fig7_nightjar.png"), fig7,
       width = 7.5, height = 3.6, dpi = 300, bg = "white")
ggsave(file.path("manuscript", "figures", "Fig7_nightjar.pdf"), fig7, width = 7.5, height = 3.6)
message("Figure 7 written to manuscript/figures/")
