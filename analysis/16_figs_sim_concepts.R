# =============================================================================
# 16_figs_sim_concepts.R
# Three conceptual figures of the simulation design for Appendix S1, Section
# S1.0, drawn from the generating equations of simulate_fp() (no fits):
#   Fig_gamma_scale     the spread of the site-level false-positive rate p10_i
#                       for each strength of the confusion gamma_FP. As w is
#                       standardized, p10_i = plogis(logit(p10) + gamma_FP * w)
#                       has the same distribution at every cor(w, x).
#   Fig_beta_scenario   scenario II: p10_i ~ Beta(p10 * 2, (1 - p10) * 2) in one
#                       landscape of 300 sites, independent of x.
#   Fig_apparent_occ    why structured confusion biases the environmental
#                       effect: the occupancy that a model with the
#                       false-positive rate held at p10 would need to reproduce
#                       the expected detection rate at each x,
#                       psi_app = psi + (1 - psi) * (E[p10_i | x] - p10) / (p11 - p10),
#                       against the true occupancy psi(x).
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
library(tidyverse)
library(patchwork)

theme_set(theme_minimal(base_size = 10) +
            theme(panel.grid.minor = element_blank(), legend.position = "top",
                  strip.text = element_text(face = "bold"),
                  plot.title = element_text(size = 10, face = "bold")))
ink <- "#52514e"
cor_cols <- c("0.3" = "#e9a15a", "0.7" = "#c0621b", "1" = "#6e3409")
lab_p10 <- as_labeller(\(p) sprintf("p10 = %.2f", as.numeric(p)))
save_fig <- function(p, name, height) {
  for (ext in c("png", "pdf"))
    ggsave(file.path("manuscript", "figures", paste0(name, ".", ext)), p,
           width = 7, height = height, dpi = 300, bg = "white")
}
b0 <- 0; b1 <- -0.8; p11 <- 0.6

# Strength of the confusion ------------------------------------------------------
q <- c(lo90 = 0.05, lo50 = 0.25, mid = 0.5, hi50 = 0.75, hi90 = 0.95)
g <- expand_grid(p10 = c(0.05, 0.20), gamma = c(0, 0.25, 0.5, 1, 1.5)) |>
  mutate(v = map2(p10, gamma, \(p, gm) setNames(plogis(qlogis(p) + gm * qnorm(q)), names(q)))) |>
  unnest_wider(v) |>
  mutate(grid = case_when(gamma == 0 ~ "homogeneous",
                          p10 == 0.05 | gamma == 1.5 ~ "simulated",
                          TRUE ~ "not simulated"))
fig_g <- ggplot(g, aes(factor(gamma), mid)) +
  geom_hline(aes(yintercept = p10), linetype = "dashed", linewidth = 0.4, colour = ink) +
  geom_linerange(aes(ymin = lo90, ymax = hi90, alpha = grid), linewidth = 0.8, colour = "#c0621b") +
  geom_linerange(aes(ymin = lo50, ymax = hi50, alpha = grid), linewidth = 2.6, colour = "#c0621b") +
  geom_point(aes(alpha = grid), size = 2, colour = "#6e3409") +
  geom_text(aes(y = hi90, label = sprintf("%.2f", hi90)), vjust = -0.6, size = 2.7, colour = ink) +
  facet_wrap(~p10, labeller = lab_p10) +
  scale_alpha_manual(values = c(homogeneous = 1, simulated = 1, "not simulated" = 0.3), guide = "none") +
  scale_y_continuous(limits = c(0, 0.85), breaks = seq(0, 0.8, 0.2)) +
  labs(x = expression("Strength of the confusion "*gamma[FP]),
       y = expression("Site-level false-positive rate "*italic(p)[paste(10, ",", italic(i))]))
save_fig(fig_g, "Fig_gamma_scale", 3.2)

# Scenario II ----------------------------------------------------------------------
set.seed(2026)
nsite <- 300; conc <- 2
x <- as.numeric(scale(rnorm(nsite)))
bdat <- expand_grid(p10 = c(0.05, 0.20), site = seq_len(nsite)) |>
  mutate(x = x[site], p10_i = rbeta(n(), p10 * conc, (1 - p10) * conc))
blab <- distinct(bdat, p10) |>
  mutate(label = sprintf("%.0f%% of sites below 0.01\n%.0f%% above 0.5",
                         100 * pbeta(0.01, p10 * conc, (1 - p10) * conc),
                         100 * pbeta(0.5, p10 * conc, (1 - p10) * conc, lower.tail = FALSE)))
fb_a <- ggplot(bdat, aes(p10_i)) +
  geom_histogram(breaks = seq(0, 1, 0.025), fill = ink, colour = "white", linewidth = 0.2) +
  geom_vline(aes(xintercept = p10), linetype = "dashed", linewidth = 0.4, colour = "#c0621b") +
  geom_text(data = blab, aes(x = 0.98, y = Inf, label = label), hjust = 1, vjust = 1.3,
            size = 2.8, colour = ink, lineheight = 0.95) +
  facet_wrap(~p10, labeller = lab_p10) +
  labs(x = expression("Site-level false-positive rate "*italic(p)[paste(10, ",", italic(i))]),
       y = "Sites", title = "a  Most sites have almost no false positives, a few have many")
fb_b <- ggplot(bdat, aes(x, p10_i)) +
  geom_hline(aes(yintercept = p10), linetype = "dashed", linewidth = 0.4, colour = "#c0621b") +
  geom_point(size = 0.9, alpha = 0.6, colour = ink) +
  facet_wrap(~p10, labeller = lab_p10) +
  scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25)) +
  labs(x = "Occupancy covariate x",
       y = expression(italic(p)[paste(10, ",", italic(i))]),
       title = "b  The rate does not follow the occupancy covariate")
save_fig(fb_a / fb_b, "Fig_beta_scenario", 5)

# Apparent occupancy ------------------------------------------------------------------
zq <- qnorm(ppoints(401))                    # quadrature over the noise of w given x
e_p10 <- function(xv, rho, p10, gm)
  map_dbl(xv, \(xx) mean(plogis(qlogis(p10) + gm * (rho * xx + sqrt(1 - rho^2) * zq))))
xs <- seq(-2.5, 2.5, length.out = 201)
app <- expand_grid(p10 = c(0.05, 0.20), rho = c(0.3, 0.7, 1)) |>
  mutate(d = pmap(list(rho, p10), \(r, p) {
    psi <- plogis(b0 + b1 * xs)
    tibble(x = xs, psi_app = psi + (1 - psi) * (e_p10(xs, r, p, 1.5) - p) / (p11 - p))
  })) |>
  unnest(d) |>
  mutate(rho_f = factor(rho, c(0.3, 0.7, 1), names(cor_cols)))
truth <- expand_grid(p10 = c(0.05, 0.20), x = xs) |> mutate(psi = plogis(b0 + b1 * x))
fig_app <- ggplot(app, aes(x, psi_app, colour = rho_f)) +
  geom_line(data = truth, aes(x, psi), inherit.aes = FALSE, linewidth = 1, colour = "black") +
  geom_line(linewidth = 0.8) +
  geom_text(data = distinct(truth, p10), aes(x = 0.1, y = 0.2, label = "true occupancy"),
            inherit.aes = FALSE, size = 3, colour = "black", hjust = 0) +
  facet_wrap(~p10, labeller = lab_p10) +
  scale_colour_manual(values = cor_cols, name = "cor(w, x)") +
  coord_cartesian(ylim = c(0, 1)) +
  labs(x = "Occupancy covariate x", y = "Occupancy")
save_fig(fig_app, "Fig_apparent_occ", 3.4)
