# =============================================================================
# fp_diagnostics.R  —  reusable tools built on the calibration machinery.
#
# Two user-facing functions for someone planning a false-positive occupancy
# study of their own:
#
#   fp_calibration_check()  Given your design and the false-positive structure
#                           you suspect, simulate and report whether the
#                           constant-p10 correction's 95% intervals actually
#                           contain the truth 95% of the time, for p10, psi and
#                           the covariate slope b1. Returns the coverage table
#                           and prints a plain verdict.
#
#   how_much_to_verify()    Sweep the fraction of sites verified and return the
#                           coverage-vs-verification curve, so you can read off
#                           how much manual annotation your design needs, and
#                           see when verifying more stops helping (the signature
#                           of structured confusion, which needs the fix in
#                           fp_fix.R, not more verification).
#
# Both wrap simulate_fp()/fit_both()/run_pilot()/summarise_pilot() from
# R/fp_sim_pilot.R; source that first. COST: each replicate is one Stan fit,
# ~180 s on a modern laptop, so total time is roughly
#     (number of cells) x reps x 180 s / workers.
# Keep reps modest (50 is usually enough to separate calibrated from not) and
# raise it only to pin a borderline number.
# =============================================================================

# ---- helper: one-line verdict from a coverage value -------------------------
.fp_verdict <- function(cov, what, nominal = 0.95, tol = 0.05) {
  if (is.na(cov)) return(sprintf("  %-28s coverage NA (model did not fit)", what))
  flag <- if (cov >= nominal - tol) "OK" else if (cov >= 0.80) "LOW" else "COLLAPSED"
  sprintf("  %-28s %.2f  [%s]", what, cov, flag)
}

#' Check interval calibration of the constant-p10 correction for your design.
#'
#' @param nsite,K,psi,p11,p10,b1 the design and truth (b1 is the covariate slope).
#' @param verified_coverage fraction of sites that get verified clips.
#' @param conf_effect,conf_cor structured-confusion strength and its correlation
#'        with the covariate (0 = homogeneous; >0 with cor>0 = confusion).
#' @param sigma_p10,p10_beta_conc optional unstructured heterogeneity.
#' @param reps replicates (Stan fits). @param stan_file the constant-p10 model.
#' @return the per-cell coverage tibble (invisibly); prints a verdict.
fp_calibration_check <- function(nsite = 300, K = 20, psi = 0.5, p11 = 0.6,
                                 p10 = 0.05, b1 = -0.8, verified_coverage = 0.30,
                                 conf_effect = 0, conf_cor = 0,
                                 sigma_p10 = 0, p10_beta_conc = NA,
                                 reps = 50,
                                 stan_file = "inst/stan/fp_occupancy_re_toggle.stan",
                                 parallel = TRUE, workers = 16,
                                 fit_args = list(iter_warmup = 1000, iter_sampling = 1000,
                                                 adapt_delta = 0.95, parallel_chains = 1)) {
  design <- data.frame(p10 = p10, verified_coverage = verified_coverage,
                       nsite = nsite, K = K, psi = psi, p11 = p11,
                       sigma_p10 = sigma_p10, p10_beta_conc = p10_beta_conc,
                       conf_effect = conf_effect, conf_cor = conf_cor)
  res <- run_pilot(design, reps = reps, stan_file = stan_file,
                   parallel = parallel, workers = workers, fit_args = fit_args)
  s   <- summarise_pilot(res)
  cat(sprintf("\nCalibration check  (nsite=%d, K=%d, p10=%.2f, verify=%.0f%%, reps=%d)\n",
              nsite, K, p10, 100 * verified_coverage, reps))
  regime <- if (conf_effect != 0 && conf_cor != 0) "structured confusion"
            else if (!is.na(p10_beta_conc) || sigma_p10 > 0) "unstructured heterogeneity"
            else "homogeneous"
  cat(sprintf("  false-positive regime: %s\n", regime))
  cat(.fp_verdict(s$stan_p10_coverage95, "false-positive rate p10"), "\n")
  cat(.fp_verdict(s$stan_b1_coverage95,  "covariate slope b1"), "\n")
  if (any((s$stan_b1_coverage95 < 0.80) & (conf_effect != 0)))
    cat("  -> b1 intervals are overconfident under this confusion. Verifying more\n",
        "     will not fix it; model p10 as a function of the covariate (see fp_fix.R).\n")
  invisible(s)
}

#' Verification-coverage curve: how much to verify, and when it stops helping.
#'
#' @param coverage_grid fractions of sites verified to sweep.
#' @param include_fix if TRUE, also fit the covariate-p10 model at each level
#'        (needs R/fp_fix.R and inst/stan/fp_occupancy_fpcov.stan) so you can
#'        see the fix recover what verification cannot.
#' @return a tibble of coverage vs verification (invisibly); prints it.
how_much_to_verify <- function(nsite = 300, K = 20, psi = 0.5, p11 = 0.6,
                               p10 = 0.05, b1 = -0.8,
                               conf_effect = 1.5, conf_cor = 0.7,
                               coverage_grid = c(0.10, 0.30, 0.50, 0.70, 0.90),
                               reps = 50,
                               stan_file  = "inst/stan/fp_occupancy_re_toggle.stan",
                               fpcov_file = "inst/stan/fp_occupancy_fpcov.stan",
                               include_fix = FALSE,
                               parallel = TRUE, workers = 16,
                               fit_args = list(iter_warmup = 1000, iter_sampling = 1000,
                                               adapt_delta = 0.95, parallel_chains = 1)) {
  design <- tidyr::expand_grid(p10 = p10, verified_coverage = coverage_grid,
                               nsite = nsite, K = K, psi = psi, p11 = p11) |>
    dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA,
                  conf_effect = conf_effect, conf_cor = conf_cor)
  res <- run_pilot(design, reps = reps, stan_file = stan_file,
                   parallel = parallel, workers = workers, fit_args = fit_args)
  out <- summarise_pilot(res) |>
    dplyr::transmute(verified = .data$coverage,
                     p10_coverage95 = .data$stan_p10_coverage95,
                     b1_coverage95_constant = .data$stan_b1_coverage95,
                     b1_bias_constant = .data$stan_b1_bias)

  if (include_fix) {
    if (!exists("run_fix")) stop("include_fix = TRUE needs R/fp_fix.R sourced.")
    resf <- run_fix(design, reps = reps, fpcov_file = fpcov_file,
                    base_seed = 20000, parallel = parallel, workers = workers,
                    also_constant = FALSE, fit_args = fit_args)
    sf <- summarise_fix(resf) |>
      dplyr::transmute(verified = .data$coverage,
                       b1_coverage95_fix = .data$fixstan_b1_coverage95,
                       b1_bias_fix = .data$fixstan_b1_bias)
    out <- dplyr::left_join(out, sf, by = "verified")
  }
  cat(sprintf("\nHow much to verify  (p10=%.2f, confusion effect=%.1f, cor=%.1f, reps=%d)\n",
              p10, conf_effect, conf_cor, reps))
  print(as.data.frame(out), row.names = FALSE)
  if (include_fix)
    cat("\n  Read across: constant-p10 b1 coverage stays low as `verified` climbs,\n",
        "  while the fix (b1_coverage95_fix) recovers it. Verification anchors the\n",
        "  mean false-positive rate, not its dependence on the covariate.\n")
  else if (conf_effect != 0)
    cat("\n  If b1_coverage95_constant does not approach 0.95 as `verified` climbs,\n",
        "  the confusion is structured: set include_fix = TRUE to see the fix.\n")
  invisible(out)
}
