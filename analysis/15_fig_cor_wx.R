# =============================================================================
# 15_fig_cor_wx.R
# Figure illustrating cor(w, x), the correlation between the confusing gradient
# w and the occupancy covariate x under structured confusion. One simulated
# landscape of 300 sites, drawn as in simulate_fp():
#   w = rho * x + sqrt(1 - rho^2) * e,   logit(p10_i) = logit(p10) + gamma_FP * w_i
# The same x and e are used in every column, so only rho changes.
#   Row a  w against x, with the expected line w = rho * x.
#   Row b  the site-level false-positive rate p10_i against x (p10 = 0.05,
#          gamma_FP = 1.5): the higher rho, the more the false positives track
#          the occupancy covariate.
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(tidyverse)
library(patchwork)

theme_set(theme_minimal(base_size = 10) +
            theme(panel.grid.minor = element_blank(), legend.position = "none",
                  strip.text = element_text(face = "bold"),
                  plot.title = element_text(size = 10, face = "bold")))
ink <- "#52514e"
cor_cols <- c("0.3" = "#e9a15a", "0.7" = "#c0621b", "1" = "#6e3409")

set.seed(2026)
nsite <- 300
x <- as.numeric(scale(rnorm(nsite)))
e <- rnorm(nsite)
p10 <- 0.05; gamma_fp <- 1.5

d <- expand_grid(rho = c(0.3, 0.7, 1), site = seq_len(nsite)) |>
  mutate(x = x[site],
         w = rho * x + sqrt(1 - rho^2) * e[site],
         p10_i = plogis(qlogis(p10) + gamma_fp * w),
         rho_f = factor(rho, c(0.3, 0.7, 1), names(cor_cols)))
lab_rho <- as_labeller(\(r) paste0("cor(w, x) = ", r))

fa <- ggplot(d, aes(x, w, colour = rho_f)) +
  geom_point(size = 0.9, alpha = 0.6) +
  geom_abline(aes(slope = rho, intercept = 0), data = distinct(d, rho, rho_f),
              linewidth = 0.6, colour = ink) +
  facet_wrap(~rho_f, labeller = lab_rho) +
  scale_colour_manual(values = cor_cols) +
  coord_cartesian(xlim = c(-3, 3), ylim = c(-3.5, 3.5)) +
  labs(x = "Occupancy covariate x", y = "Confusing gradient w",
       title = "a  The confusing gradient follows the occupancy covariate")

fb <- ggplot(d, aes(x, p10_i, colour = rho_f)) +
  geom_hline(yintercept = p10, linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_point(size = 0.9, alpha = 0.6) +
  facet_wrap(~rho_f, labeller = lab_rho) +
  scale_colour_manual(values = cor_cols) +
  scale_y_continuous(breaks = seq(0, 1, 0.25)) +
  coord_cartesian(xlim = c(-3, 3), ylim = c(0, 1)) +
  labs(x = "Occupancy covariate x",
       y = expression("False-positive rate "*italic(p)[paste(10, ",", italic(i))]),
       title = expression(bold("b  So do the false positives ("*italic(p)[10]*" = 0.05, "*gamma[FP]*" = 1.5)")))

fig <- fa / fb + plot_layout(heights = c(1, 0.85))
for (ext in c("png", "pdf"))
  ggsave(file.path("manuscript", "figures", paste0("Fig_cor_wx.", ext)), fig,
         width = 7, height = 5.2, dpi = 300, bg = "white")
