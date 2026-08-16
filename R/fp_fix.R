# =============================================================================
# fp_fix.R  —  "the fix": model the false-positive rate as a function of the
#              covariate, and show it recovers the occupancy slope b1 that a
#              constant-p10 model loses under structured confusion.
# -----------------------------------------------------------------------------
# fit_fix()  fits, on ONE simulated dataset:
#   (1) the covariate-p10 Bayesian model (inst/stan/fp_occupancy_fpcov.stan),
#       logit(p10_i) = gamma0 + gamma_fp * xs, with the same gap-at-reference
#       identifiability as the constant model;
#   (2) unmarked::occuFP with FPformula = ~ xs, the same fix in the frequentist
#       framework (so the recovery is shown to be a property of the estimand,
#       not of one software);
#   (3) OPTIONALLY the constant-p10 model (fp_occupancy_re_toggle.stan) on the
#       SAME dataset, for a paired failing baseline (used on the conf_cor = 1
#       cells, where no constant-p10 result exists yet).
# It returns ONE row with b1 point estimates, 95% coverage and intervals for
# each fitted model, plus convergence and the estimated FP slope.
#
# run_fix() maps fit_fix() over reps x cells with furrr, exactly like
# run_pilot(). Compile the models INSIDE each task (external pointers do not
# survive being shipped to a worker; the compiled binary is cached).
#
# Needs simulate_fp() from R/fp_sim_pilot.R; source that file first.
# =============================================================================

fit_fix <- function(sim, fpcov_mod, const_mod = NULL,
                    chains = 4, iter_warmup = 1000, iter_sampling = 1000,
                    adapt_delta = 0.95, seed = 1, parallel_chains = chains,
                    also_constant = FALSE, verbose = FALSE) {

  tr <- sim$truth
  q  <- function(v, p) unname(stats::quantile(v, p))
  in95 <- function(true, v) as.logical(true >= q(v, .025) & true <= q(v, .975))

  # ---- FP design: the standardized occupancy covariate xs is column 2 of X ----
  sd_fp <- sim$stan_data
  sd_fp$Kfp <- 1L
  sd_fp$Xfp <- matrix(sim$stan_data$X[, 2], ncol = 1)   # xs, no intercept

  ## ---------- (1) covariate-p10 Bayesian model ----------
  fixstan <- tryCatch({
    fit <- fpcov_mod$sample(data = sd_fp, chains = chains,
                            parallel_chains = parallel_chains,
                            iter_warmup = iter_warmup, iter_sampling = iter_sampling,
                            adapt_delta = adapt_delta, seed = seed,
                            refresh = if (verbose) 200 else 0)
    ds   <- fit$diagnostic_summary(quiet = TRUE)
    smry <- fit$summary(c("beta", "gamma_fp", "p10_ref", "p10_bar"))
    dr   <- fit$draws(variables = c("beta", "gamma_fp", "p10_ref", "p10_bar"),
                      format = "df")
    list(ok = TRUE,
         max_rhat = max(smry$rhat, na.rm = TRUE),
         min_ess  = min(smry$ess_bulk, na.rm = TRUE),
         ndiv     = sum(ds$num_divergent),
         runtime  = as.numeric(fit$time()$total),
         b1_est = mean(dr$`beta[2]`), b1_cov = in95(tr$b1, dr$`beta[2]`),
         b1_lo  = q(dr$`beta[2]`, .025), b1_hi = q(dr$`beta[2]`, .975),
         gamma_fp_est = mean(dr$`gamma_fp[1]`),
         gamma_fp_cov = in95(tr$conf_effect * tr$conf_cor, dr$`gamma_fp[1]`),  # xs-aligned part of the confusion
         p10_ref_est = mean(dr$p10_ref), p10_bar_est = mean(dr$p10_bar))
  }, error = function(e) list(ok = FALSE, msg = conditionMessage(e)))

  ## ---------- (2) occuFP with FPformula = ~ xs (the frequentist fix) ----------
  fixocc <- tryCatch({
    umf <- unmarked::unmarkedFrameOccuFP(
      y = sim$umf$y, siteCovs = sim$umf$siteCovs,
      obsCovs = sim$umf$obsCovs, type = sim$umf$type)
    t0 <- proc.time()[["elapsed"]]
    m  <- unmarked::occuFP(detformula = ~ method, FPformula = ~ xs,
                           Bformula = ~ 1, stateformula = ~ xs, data = umf)
    rt <- proc.time()[["elapsed"]] - t0
    se     <- tryCatch(unmarked::SE(m), error = function(e) NA_real_)
    conv   <- tryCatch(m@opt$convergence, error = function(e) NA_integer_)
    degen  <- any(!is.finite(se)) || any(abs(coef(m)) > 10) || (!is.na(conv) && conv != 0)
    ci     <- tryCatch(suppressWarnings(unname(confint(m, type = "state", level = 0.95)[2, ])),
                       error = function(e) c(NA_real_, NA_real_))
    b1e    <- unname(coef(m, type = "state")[2])
    inCI   <- function(true, lo, hi) if (is.finite(lo) && is.finite(hi))
                as.logical(true >= lo & true <= hi) else NA
    list(ok = TRUE, degenerate = degen, runtime = rt,
         b1_est = b1e, b1_lo = ci[1], b1_hi = ci[2], b1_cov = inCI(tr$b1, ci[1], ci[2]))
  }, error = function(e) list(ok = FALSE, degenerate = TRUE, msg = conditionMessage(e)))

  ## ---------- (3) optional constant-p10 baseline on the SAME data ----------
  conststan <- if (also_constant && !is.null(const_mod)) tryCatch({
    fit <- const_mod$sample(data = sim$stan_data, chains = chains,
                            parallel_chains = parallel_chains,
                            iter_warmup = iter_warmup, iter_sampling = iter_sampling,
                            adapt_delta = adapt_delta, seed = seed, refresh = 0)
    ds  <- fit$diagnostic_summary(quiet = TRUE)
    sm  <- fit$summary("beta")
    dr  <- fit$draws(variables = "beta", format = "df")
    list(ok = TRUE, max_rhat = max(sm$rhat, na.rm = TRUE), ndiv = sum(ds$num_divergent),
         b1_est = mean(dr$`beta[2]`), b1_cov = in95(tr$b1, dr$`beta[2]`),
         b1_lo = q(dr$`beta[2]`, .025), b1_hi = q(dr$`beta[2]`, .975))
  }, error = function(e) list(ok = FALSE, msg = conditionMessage(e))) else list(ok = FALSE)

  ## ---------- one stacked row ----------
  g <- function(x, f, default = NA) if (isTRUE(x$ok)) x[[f]] else default
  data.frame(
    nsite = sim$design$nsite, K = sim$design$K,
    verified_coverage = sim$design$verified_coverage,
    n_verified_sites  = sim$design$n_verified_sites,
    true_p10 = tr$p10, true_b1 = tr$b1,
    true_conf_effect = tr$conf_effect, true_conf_cor = tr$conf_cor,
    # ----- (1) covariate-p10 Stan (the fix) -----
    fixstan_ok       = isTRUE(fixstan$ok),
    fixstan_max_rhat = g(fixstan, "max_rhat"),
    fixstan_ndiv     = g(fixstan, "ndiv"),
    fixstan_runtime  = g(fixstan, "runtime"),
    fixstan_b1_est   = g(fixstan, "b1_est"),  fixstan_b1_cov = g(fixstan, "b1_cov"),
    fixstan_b1_lo    = g(fixstan, "b1_lo"),   fixstan_b1_hi  = g(fixstan, "b1_hi"),
    fixstan_gamma_fp = g(fixstan, "gamma_fp_est"),
    fixstan_p10_ref  = g(fixstan, "p10_ref_est"),
    fixstan_p10_bar  = g(fixstan, "p10_bar_est"),
    # ----- (2) occuFP with FPformula = ~ xs -----
    fixocc_ok        = isTRUE(fixocc$ok),
    fixocc_degenerate = isTRUE(fixocc$degenerate),
    fixocc_b1_est    = g(fixocc, "b1_est"),   fixocc_b1_cov = g(fixocc, "b1_cov"),
    fixocc_b1_lo     = g(fixocc, "b1_lo"),    fixocc_b1_hi  = g(fixocc, "b1_hi"),
    # ----- (3) constant-p10 baseline (only when also_constant) -----
    const_ok         = isTRUE(conststan$ok),
    const_b1_est     = g(conststan, "b1_est"), const_b1_cov = g(conststan, "b1_cov"),
    const_max_rhat   = g(conststan, "max_rhat"), const_ndiv = g(conststan, "ndiv"),
    stringsAsFactors = FALSE
  )
}


run_fix <- function(design, reps = 100,
                    fpcov_file = "inst/stan/fp_occupancy_fpcov.stan",
                    const_file = "inst/stan/fp_occupancy_re_toggle.stan",
                    base_seed = 9000, parallel = FALSE, workers = NULL,
                    also_constant = FALSE, fit_args = list()) {

  tasks <- tidyr::expand_grid(rep = seq_len(reps), cell = seq_len(nrow(design)))
  tasks$seed <- base_seed + seq_len(nrow(tasks))

  run_one <- function(rep, cell, seed) {
    cfg <- design[cell, , drop = FALSE]
    fpcov_mod <- cmdstanr::cmdstan_model(fpcov_file)                 # cached compile
    const_mod <- if (also_constant) cmdstanr::cmdstan_model(const_file) else NULL
    beta_conc <- if (!is.null(cfg$p10_beta_conc) && !is.na(cfg$p10_beta_conc)) cfg$p10_beta_conc else NULL
    sim <- simulate_fp(nsite = cfg$nsite, K = cfg$K, psi = cfg$psi, p11 = cfg$p11,
                       p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
                       sigma_p10     = if (!is.null(cfg$sigma_p10))   cfg$sigma_p10   else 0,
                       p10_beta_conc = beta_conc,
                       conf_effect   = if (!is.null(cfg$conf_effect)) cfg$conf_effect else 0,
                       conf_cor      = if (!is.null(cfg$conf_cor))    cfg$conf_cor    else 0,
                       seed = seed)
    message(sprintf("[fix rep %d | cell %d]  p10=%.2f  conf=%.2f  cor=%.2f  cov=%.2f",
                    rep, cell, cfg$p10, cfg$conf_effect, cfg$conf_cor, cfg$verified_coverage))
    cbind(rep = rep, cell = cell,
          do.call(fit_fix, c(list(sim = sim, fpcov_mod = fpcov_mod, const_mod = const_mod,
                                  also_constant = also_constant), fit_args)))
  }

  if (parallel) {
    if (!requireNamespace("furrr", quietly = TRUE) ||
        !requireNamespace("future", quietly = TRUE))
      stop("parallel = TRUE needs 'furrr' and 'future'.")
    nw <- if (is.null(workers)) max(1L, future::availableCores() - 2L) else workers
    future::plan(future::multisession, workers = nw)
    on.exit(future::plan(future::sequential), add = TRUE)
    rows <- furrr::future_pmap(tasks, run_one,
                               .options = furrr::furrr_options(seed = TRUE,
                                                               packages = "unmarked"))
  } else {
    rows <- purrr::pmap(tasks, run_one)
  }
  purrr::list_rbind(rows)
}


summarise_fix <- function(res) {
  res |>
    dplyr::mutate(
      fixstan_conv = as.numeric(.data$fixstan_ndiv == 0 & .data$fixstan_max_rhat < 1.01),
      fixstan_b1_bias = .data$fixstan_b1_est - .data$true_b1,
      fixocc_b1_bias  = ifelse(.data$fixocc_degenerate, NA_real_, .data$fixocc_b1_est - .data$true_b1),
      const_b1_bias   = .data$const_b1_est - .data$true_b1) |>
    dplyr::group_by(p10 = .data$true_p10, coverage = .data$verified_coverage,
                    conf_effect = .data$true_conf_effect, conf_cor = .data$true_conf_cor) |>
    dplyr::summarise(
      fixstan_conv_rate     = mean(.data$fixstan_conv, na.rm = TRUE),
      fixstan_b1_coverage95 = mean(as.numeric(.data$fixstan_b1_cov), na.rm = TRUE),
      fixstan_b1_bias       = mean(.data$fixstan_b1_bias, na.rm = TRUE),
      fixstan_gamma_fp      = mean(.data$fixstan_gamma_fp,  na.rm = TRUE),
      fixocc_b1_coverage95  = mean(as.numeric(.data$fixocc_b1_cov), na.rm = TRUE),
      fixocc_b1_bias        = mean(.data$fixocc_b1_bias, na.rm = TRUE),
      const_b1_coverage95   = mean(as.numeric(.data$const_b1_cov), na.rm = TRUE),
      const_b1_bias         = mean(.data$const_b1_bias, na.rm = TRUE),
      fixstan_secs_per_fit  = mean(.data$fixstan_runtime, na.rm = TRUE),
      .groups = "drop")
}
