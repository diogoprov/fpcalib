# =============================================================================
# 09_revision_summary.R
# Summaries of the revision checks:
#   items 1 and 3 (07_revision_checks.R): coverage, bias, RMSE and interval
#     width of the occupancy slope and of the mean false-positive rate, per
#     cell and model, with Monte Carlo standard errors;
#   item 2 (07_revision_checks.R): how often leave-one-site-out
#     cross-validation prefers fp ~ x to fp ~ 1, and how often the posterior
#     predictive check flags fp ~ 1, under structured confusion (power) and
#     homogeneous false positives (false alarms);
#   item 4 (08_observation_confirmation.R): the same summaries under the
#     observation-confirmation design, including the effect of the confusing
#     gradient (fp ~ w; true value 1.5), and, from 10_obsconfirm_weak.R, the
#     same summaries at the weaker confusion effects 0.5 and 1.0, and, from
#     11_obsconfirm_clare.R, at correlation 1.0 with a model ignoring false
#     positives; and, from 12_random_fp_long.R, item 3 with 2000 + 2000
#     iterations;
#   item 5 (01_run_simulation.R): interval width and RMSE of the main study.
# Reads the per-task files in data/revision_jobs/, data/obsconfirm_jobs/,
# data/obsconfirm_weak_jobs/, data/obsconfirm_clare_jobs/ and
# data/revision_rfp_long_jobs/,
# so it also works on a run still in progress. Writes
# data/fp_revision_summary.rds, CSV tables in analysis/tables/ and figures
# in analysis/figures/ (neither tracked by git).
# Run from the compendium root:
#   RENV_ACTIVATE_PROJECT=FALSE Rscript analysis/09_revision_summary.R
# =============================================================================
read_jobs <- function(dir) {
  files <- list.files(dir, pattern = "[.]rds$", full.names = TRUE)
  if (!length(files)) return(NULL)
  purrr::map(files, readRDS) |> purrr::list_rbind()
}

# coverage, bias, RMSE and width of one estimate, with Monte Carlo SEs
score <- function(est, lo, hi, truth) {
  ok <- !is.na(est) & !is.na(lo) & !is.na(hi)   # degenerate fits have no interval
  est <- est[ok]; lo <- lo[ok]; hi <- hi[ok]; truth <- truth[ok]
  n <- length(est)
  cover <- mean(lo <= truth & truth <= hi)
  err <- est - truth
  data.frame(n = n, coverage = cover, coverage_mcse = sqrt(cover * (1 - cover) / n),
             bias = mean(err), bias_mcse = stats::sd(err) / sqrt(n),
             rmse = sqrt(mean(err^2)), width = mean(hi - lo))
}

summarise_fits <- function(res, keys) {
  groups <- split(res, res[c(keys, "model")], drop = TRUE)
  purrr::map(groups, function(g) {
    cbind(g[1, c(keys, "model")],
          slope = score(g$b1_est, g$b1_lo, g$b1_hi, g$true_b1),
          p10 = score(g$p10_est, g$p10_lo, g$p10_hi,
                      if ("true_p10_marginal" %in% names(g)) g$true_p10_marginal
                      else g$true_p10_bar)[c("coverage", "bias", "rmse", "width")],
          rhat_over_1.01 = mean(g$max_rhat > 1.01, na.rm = TRUE),
          divergent = mean(g$ndiv > 0, na.rm = TRUE),
          failed = mean(!g$ok),
          minutes = stats::median(g$seconds, na.rm = TRUE) / 60)
  }) |> purrr::list_rbind()
}

out <- list()

# --- items 1 to 3 -------------------------------------------------------------
rev <- read_jobs(file.path("data", "revision_jobs"))
if (!is.null(rev)) {
  keys <- c("regime", "p10", "verified_coverage")
  out$fits <- summarise_fits(rev, keys)
  # item 2: paired comparison of fp ~ x against fp ~ 1 on the same dataset
  pairs <- split(rev[rev$model %in% c("constant", "fp_x"), ],
                 rev[rev$model %in% c("constant", "fp_x"), c("run", "rep", "cell")], drop = TRUE)
  cmp <- purrr::map(pairs, function(g) {
    if (nrow(g) != 2 || !all(g$ok)) return(NULL)
    c0 <- g[g$model == "constant", ]
    c1 <- g[g$model == "fp_x", ]
    d <- c1$elpd_i[[1]] - c0$elpd_i[[1]]
    data.frame(regime = c0$regime, p10 = c0$p10, verified_coverage = c0$verified_coverage,
               elpd_diff = sum(d), se_diff = sqrt(length(d) * stats::var(d)),
               ppc_p_constant = c0$ppc_p, ppc_p_fp_x = c1$ppc_p)
  }) |> purrr::list_rbind()
  out$detection <- purrr::map(split(cmp, cmp[keys], drop = TRUE), function(g) {
    cbind(g[1, keys], n = nrow(g),
          loo_prefers_fp_x = mean(g$elpd_diff > 0),
          loo_prefers_fp_x_2se = mean(g$elpd_diff > 2 * g$se_diff),
          loo_prefers_fp_x_4 = mean(g$elpd_diff > 4),
          median_elpd_diff = stats::median(g$elpd_diff),
          ppc_flags_constant_05 = mean(g$ppc_p_constant < 0.05),
          ppc_flags_fp_x_05 = mean(g$ppc_p_fp_x < 0.05))
  }) |> purrr::list_rbind()
  out$revision_progress <- c(datasets = length(unique(paste(rev$run, rev$rep, rev$cell))),
                             fits = nrow(rev))
}

# --- item 4 -------------------------------------------------------------------
obs <- read_jobs(file.path("data", "obsconfirm_jobs"))
if (!is.null(obs)) {
  obs$regime <- ifelse(obs$conf_effect > 0, "structured", "homogeneous")
  out$obsconfirm <- summarise_fits(obs, c("regime", "p10", "frac_confirmed"))
  w <- obs[obs$model == "fp_w" & obs$ok, ]
  if (nrow(w)) {
    out$obsconfirm_fp_w <- purrr::map(split(w, w[c("p10", "frac_confirmed")], drop = TRUE),
      function(g) cbind(g[1, c("p10", "frac_confirmed")],
                        score(g$fp_w_est, g$fp_w_lo, g$fp_w_hi, rep(1.5, nrow(g))))) |>
      purrr::list_rbind()
  }
  out$obsconfirm_progress <- c(datasets = length(unique(paste(obs$rep, obs$cell))),
                               fits = nrow(obs))
}
# weaker confusion under observation confirmation (10_obsconfirm_weak.R)
weak <- read_jobs(file.path("data", "obsconfirm_weak_jobs"))
if (!is.null(weak)) {
  out$obsconfirm_weak <- summarise_fits(weak, c("conf_effect", "p10", "frac_confirmed"))
  out$obsconfirm_weak_progress <- c(datasets = length(unique(paste(weak$rep, weak$cell))),
                                    fits = nrow(weak))
}
# random_fp with 2000 + 2000 iterations (12_random_fp_long.R)
long <- read_jobs(file.path("data", "revision_rfp_long_jobs"))
if (!is.null(long)) {
  out$random_fp_long <- summarise_fits(long, c("regime", "p10", "verified_coverage"))
  out$random_fp_long$median_min_ess_bulk <- vapply(
    split(long, long[c("p10", "verified_coverage")], drop = TRUE),
    function(g) stats::median(g$min_ess_bulk, na.rm = TRUE), numeric(1))[
      paste(out$random_fp_long$p10, out$random_fp_long$verified_coverage, sep = ".")]
  out$random_fp_long_progress <- c(datasets = nrow(long), fits = nrow(long))
}
# false positives on the occupancy covariate itself (11_obsconfirm_clare.R)
clare <- read_jobs(file.path("data", "obsconfirm_clare_jobs"))
if (!is.null(clare)) {
  out$obsconfirm_clare <- summarise_fits(clare, c("conf_effect", "p10", "frac_confirmed"))
  out$obsconfirm_clare_progress <- c(datasets = length(unique(paste(clare$rep, clare$cell))),
                                     fits = nrow(clare))
}

# --- item 5 -------------------------------------------------------------------
main <- readRDS(file.path("data", "fp_sim_results.rds"))
main$regime <- ifelse(main$true_conf_effect > 0, "structured",
                      ifelse(main$true_beta_conc > 0, "unstructured", "homogeneous"))
out$main_width_rmse <- purrr::map(
  split(main, main[c("regime", "true_p10", "verified_coverage")], drop = TRUE),
  function(g) cbind(g[1, c("regime", "true_p10", "verified_coverage")],
                    stan = score(g$stan_b1_est, g$stan_b1_lo, g$stan_b1_hi, g$true_b1),
                    occufp = score(g$occufp_b1_est, g$occufp_b1_lo, g$occufp_b1_hi,
                                   g$true_b1)[c("coverage", "rmse", "width")])) |>
  purrr::list_rbind()

# --- figures ------------------------------------------------------------------
library(ggplot2)
fig_dir <- file.path("analysis", "figures")
dir.create(fig_dir, showWarnings = FALSE)
okabe <- c(constant = "#7F7F7F", fp_x = "#0072B2", fp_w = "#009E73", random_fp = "#D55E00")
theme_set(theme_bw(base_size = 11) + theme(legend.position = "top"))
dodge <- position_dodge(width = 0.5)
lab_cell <- function(d) sprintf("p10 = %.2f, %g%% verified", d$p10, 100 * d$verified_coverage)
save_fig <- function(p, name, w = 8, h = 4.5) ggsave(file.path(fig_dir, name), p, width = w, height = h, dpi = 200)

if (!is.null(out$fits)) {
  f <- out$fits
  f$cell <- lab_cell(f)
  # item 1: cost of fp ~ x when false positives are homogeneous
  h <- f[f$regime == "homogeneous", ]
  if (nrow(h)) {
    long <- rbind(
      data.frame(h[c("cell", "model")], measure = "coverage", value = h$slope.coverage,
                 lo = h$slope.coverage - 2 * h$slope.coverage_mcse,
                 hi = pmin(1, h$slope.coverage + 2 * h$slope.coverage_mcse)),
      data.frame(h[c("cell", "model")], measure = "interval width", value = h$slope.width,
                 lo = NA, hi = NA),
      data.frame(h[c("cell", "model")], measure = "RMSE", value = h$slope.rmse, lo = NA, hi = NA))
    p <- ggplot(long, aes(cell, value, colour = model)) +
      geom_point(position = dodge) +
      geom_errorbar(aes(ymin = lo, ymax = hi), width = 0, position = dodge, na.rm = TRUE) +
      facet_wrap(~ measure, scales = "free_y", ncol = 1) +
      scale_colour_manual(values = okabe) + coord_flip() +
      labs(x = NULL, y = NULL, colour = NULL,
           title = "Item 1: occupancy slope under homogeneous false positives")
    save_fig(p, "item1_cost_fp_x.png", h = 8)
  }
  # item 3: unstructured false positives, constant rate vs site random effect
  u <- f[f$regime == "unstructured", ]
  if (nrow(u)) {
    long <- rbind(
      data.frame(u[c("cell", "model")], measure = "coverage of the slope", value = u$slope.coverage,
                 lo = u$slope.coverage - 2 * u$slope.coverage_mcse,
                 hi = pmin(1, u$slope.coverage + 2 * u$slope.coverage_mcse)),
      data.frame(u[c("cell", "model")], measure = "coverage of p10_bar", value = u$p10.coverage,
                 lo = NA, hi = NA),
      data.frame(u[c("cell", "model")], measure = "share of fits with R-hat > 1.01",
                 value = u$rhat_over_1.01, lo = NA, hi = NA))
    p <- ggplot(long, aes(cell, value, colour = model)) +
      geom_hline(data = data.frame(measure = c("coverage of the slope", "coverage of p10_bar"),
                                   y = 0.95), aes(yintercept = y), linetype = 2) +
      geom_point(position = dodge) +
      geom_errorbar(aes(ymin = lo, ymax = hi), width = 0, position = dodge, na.rm = TRUE) +
      facet_wrap(~ measure, ncol = 1) +
      scale_colour_manual(values = okabe) + coord_flip(ylim = c(0, 1)) +
      labs(x = NULL, y = NULL, colour = NULL,
           title = "Item 3: unstructured false positives")
    save_fig(p, "item3_random_fp.png", h = 7)
  }
}
# item 2: detection of structured confusion and false alarms
if (!is.null(out$detection)) {
  d <- out$detection
  d$cell <- lab_cell(d)
  long <- rbind(
    data.frame(d[c("regime", "cell")], check = "LOO prefers fp ~ x (difference > 2 SE)",
               rate = d$loo_prefers_fp_x_2se),
    data.frame(d[c("regime", "cell")], check = "PPC flags fp ~ 1 (p < 0.05)",
               rate = d$ppc_flags_constant_05))
  p <- ggplot(long, aes(cell, rate, fill = regime)) +
    geom_col(position = position_dodge(width = 0.8), width = 0.7) +
    facet_wrap(~ check, ncol = 1) + coord_flip(ylim = c(0, 1)) +
    scale_fill_manual(values = c(structured = "#D55E00", homogeneous = "#7F7F7F")) +
    labs(x = NULL, y = "Share of datasets", fill = NULL,
         title = "Item 2: does the model check detect structured confusion?",
         subtitle = "structured: power; homogeneous: false alarms")
  save_fig(p, "item2_detection.png", h = 6)
}
# item 4: observation confirmation
if (!is.null(out$obsconfirm)) {
  o <- out$obsconfirm
  o$p10_lab <- sprintf("p10 = %.2f", o$p10)
  p <- ggplot(o[o$regime == "structured", ],
              aes(frac_confirmed, slope.coverage, colour = model)) +
    geom_hline(yintercept = 0.95, linetype = 2) +
    geom_line() + geom_point() +
    geom_errorbar(aes(ymin = slope.coverage - 2 * slope.coverage_mcse,
                      ymax = pmin(1, slope.coverage + 2 * slope.coverage_mcse)), width = 0) +
    facet_wrap(~ p10_lab) +
    scale_colour_manual(values = okabe) +
    scale_x_continuous(labels = scales::percent) + coord_cartesian(ylim = c(0, 1)) +
    labs(x = "Automated occasions checked", y = "Coverage of the 95% CrI of the slope",
         colour = NULL, title = "Item 4: structured confusion, observation-confirmation design")
  save_fig(p, "item4_obsconfirm_coverage.png")
}
# item 4, weaker confusion: coverage by confusion effect (1.5 from 08)
if (!is.null(out$obsconfirm_weak)) {
  o <- out$obsconfirm_weak
  if (!is.null(out$obsconfirm)) {
    s15 <- out$obsconfirm[out$obsconfirm$regime == "structured" &
                            out$obsconfirm$model %in% c("constant", "fp_x"), ]
    s15$conf_effect <- 1.5
    o <- rbind(o, s15[names(o)])
  }
  o$p10_lab <- sprintf("p10 = %.2f", o$p10)
  o$effect_lab <- sprintf("confusion effect %.1f", o$conf_effect)
  p <- ggplot(o, aes(frac_confirmed, slope.coverage, colour = model)) +
    geom_hline(yintercept = 0.95, linetype = 2) +
    geom_line() + geom_point() +
    geom_errorbar(aes(ymin = slope.coverage - 2 * slope.coverage_mcse,
                      ymax = pmin(1, slope.coverage + 2 * slope.coverage_mcse)), width = 0) +
    facet_grid(p10_lab ~ effect_lab) +
    scale_colour_manual(values = okabe) +
    scale_x_continuous(labels = scales::percent) + coord_cartesian(ylim = c(0, 1)) +
    labs(x = "Automated occasions checked", y = "Coverage of the 95% CrI of the slope",
         colour = NULL, title = "Item 4: strength of confusion, observation-confirmation design")
  save_fig(p, "item4_obsconfirm_weak.png", h = 6)
}
# item 4, correlation 1.0: coverage by confusion effect, with the naive model
if (!is.null(out$obsconfirm_clare)) {
  o <- out$obsconfirm_clare
  o$p10_lab <- sprintf("p10 = %.2f", o$p10)
  o$effect_lab <- sprintf("confusion effect %.1f", o$conf_effect)
  p <- ggplot(o, aes(frac_confirmed, slope.coverage, colour = model)) +
    geom_hline(yintercept = 0.95, linetype = 2) +
    geom_line() + geom_point() +
    geom_errorbar(aes(ymin = slope.coverage - 2 * slope.coverage_mcse,
                      ymax = pmin(1, slope.coverage + 2 * slope.coverage_mcse)), width = 0) +
    facet_grid(p10_lab ~ effect_lab) +
    scale_colour_manual(values = c(okabe, naive = "#CC79A7")) +
    scale_x_continuous(labels = scales::percent) + coord_cartesian(ylim = c(0, 1)) +
    labs(x = "Automated occasions checked", y = "Coverage of the 95% interval of the slope",
         colour = NULL, title = "Item 4: false positives on the occupancy covariate (cor = 1)")
  save_fig(p, "item4_obsconfirm_clare.png", h = 6)
}
# item 5: interval width against RMSE in the main study
m <- out$main_width_rmse
p <- ggplot(m, aes(stan.rmse, stan.width, colour = regime, shape = factor(true_p10))) +
  geom_abline(slope = 3.92, intercept = 0, linetype = 3, colour = "grey50") +
  geom_point(size = 2.5) +
  scale_colour_manual(values = c(homogeneous = "#7F7F7F", unstructured = "#0072B2",
                                 structured = "#D55E00")) +
  labs(x = "RMSE of the slope", y = "Mean width of the 95% CrI", colour = NULL,
       shape = "p10", title = "Item 5: interval width does not track the error",
       subtitle = "dotted line: width of a calibrated normal interval (3.92 x RMSE)")
save_fig(p, "item5_width_rmse.png", w = 7, h = 5)

saveRDS(out, file.path("data", "fp_revision_summary.rds"))
dir.create(file.path("analysis", "tables"), showWarnings = FALSE)
purrr::iwalk(purrr::keep(out, is.data.frame), function(tab, name) {
  utils::write.csv(tab, file.path("analysis", "tables", paste0(name, ".csv")), row.names = FALSE)
})
options(width = 200)
purrr::iwalk(out, function(x, name) { cat("\n==", name, "\n"); print(x, digits = 3, row.names = FALSE) })
