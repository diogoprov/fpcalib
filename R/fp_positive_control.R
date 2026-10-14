# =============================================================================
# fp_positive_control.R  —  positive control for the structured-confusion arm
# -----------------------------------------------------------------------------
# Question: under structured confusion the constant-p10 model attenuates (or
# reverses) the occupancy slope b1, and verifying more does not rescue it. Is
# that a failure of the CONSTANT-p10 ASSUMPTION, i.e. does the correctly
# specified model (p10 depends on the confusion gradient) recover b1?
#
# Each task re-creates EXACTLY the dataset the constant-p10 model was fitted to
# in 01_run_simulation.R (same simulate_fp() call, same seed), then fits
# inst/stan/fp_occupancy_fpcov.stan with one false-positive covariate
# (Kfp = 1, Xfp = W) set to:
#   proxy_cor = 1   -> W = w, the true confusion gradient (the positive control);
#   proxy_cor < 1   -> W = proxy_cor * w + sqrt(1 - proxy_cor^2) * e, a noisy
#                      proxy (the analyst measures only a correlate of whatever
#                      fools the classifier).
# All proxy levels for one dataset share the same noise vector e, so the
# comparison across proxy levels (and against the constant model) is paired.
#
# Requires simulate_fp() to return `w` (R/fp_sim_pilot.R, returned list).
# =============================================================================


# -----------------------------------------------------------------------------
# 1. FITTER: one dataset, one W  ->  one row
# -----------------------------------------------------------------------------
fit_fpcov <- function(sim, W, stan_mod,
                      chains = 4, iter_warmup = 1000, iter_sampling = 1000,
                      adapt_delta = 0.95, seed = 1, parallel_chains = chains) {
  tr   <- sim$truth
  q    <- function(v, p) unname(stats::quantile(v, p))
  in95 <- function(true, v) as.logical(true >= q(v, .025) & true <= q(v, .975))
  vars <- c("beta", "gamma_fp", "p10_bar", "p10_ref", "p11_ref", "r11")
  sd_fp <- sim$stan_data
  sd_fp$Kfp <- 1L
  sd_fp$Xfp <- matrix(as.numeric(W), ncol = 1)       # W, no intercept

  res <- tryCatch({
    fit  <- stan_mod$sample(data = sd_fp,
                            chains = chains, parallel_chains = parallel_chains,
                            iter_warmup = iter_warmup, iter_sampling = iter_sampling,
                            adapt_delta = adapt_delta, seed = seed, refresh = 0)
    ds   <- fit$diagnostic_summary(quiet = TRUE)
    smry <- fit$summary(vars)
    dr   <- fit$draws(variables = vars, format = "df")
    list(ok = TRUE,
         max_rhat = max(smry$rhat, na.rm = TRUE),
         min_ess  = min(smry$ess_bulk, na.rm = TRUE),
         ndiv     = sum(ds$num_divergent),
         runtime  = as.numeric(fit$time()$total),
         b1_est  = mean(dr$`beta[2]`), b1_lo = q(dr$`beta[2]`, .025),
         b1_hi   = q(dr$`beta[2]`, .975), b1_cov = in95(tr$b1, dr$`beta[2]`),
         # marginal FP rate (mean over sites): same benchmark as the constant model
         p10_est = mean(dr$p10_bar), p10_cov = in95(tr$p10_marginal, dr$p10_bar),
         # p10 at W = 0 and the slope g1: only interpretable against the truth
         # when proxy_cor = 1 (with a noisy proxy their targets are attenuated)
         # (g1 below is gamma_fp[1], the slope of logit(p10) on W)
         p10_int_est = mean(dr$p10_ref), p10_int_cov = in95(tr$p10, dr$p10_ref),
         g1_est  = mean(dr$`gamma_fp[1]`), g1_lo = q(dr$`gamma_fp[1]`, .025),
         g1_hi   = q(dr$`gamma_fp[1]`, .975),
         g1_cov  = in95(tr$conf_effect, dr$`gamma_fp[1]`),
         psi_est = mean(plogis(dr$`beta[1]`)))
  }, error = function(e) list(ok = FALSE, msg = conditionMessage(e)))

  g <- function(f) if (isTRUE(res$ok)) res[[f]] else NA
  data.frame(
    n_verified_sites = sim$design$n_verified_sites,
    true_p10 = tr$p10, true_p10_marginal = tr$p10_marginal,
    true_conf_effect = tr$conf_effect, true_conf_cor = tr$conf_cor,
    true_b1 = tr$b1,
    W_cor_w = as.numeric(stats::cor(W, sim$w)),        # realized proxy quality
    fpcov_ok = isTRUE(res$ok),
    fpcov_msg = if (isTRUE(res$ok)) NA_character_ else res$msg,
    fpcov_max_rhat = g("max_rhat"), fpcov_min_ess = g("min_ess"),
    fpcov_ndiv = g("ndiv"), fpcov_runtime = g("runtime"),
    fpcov_b1_est = g("b1_est"), fpcov_b1_lo = g("b1_lo"), fpcov_b1_hi = g("b1_hi"),
    fpcov_b1_cov = g("b1_cov"),
    fpcov_p10_est = g("p10_est"), fpcov_p10_cov = g("p10_cov"),
    fpcov_p10_int_est = g("p10_int_est"), fpcov_p10_int_cov = g("p10_int_cov"),
    fpcov_g1_est = g("g1_est"), fpcov_g1_lo = g("g1_lo"), fpcov_g1_hi = g("g1_hi"),
    fpcov_g1_cov = g("g1_cov"),
    fpcov_psi_est = g("psi_est"),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# 2. DRIVER: reps x cells, seeds identical to run_pilot()
# -----------------------------------------------------------------------------
# run_pilot() builds tasks <- expand_grid(rep = 1:reps, cell = 1:nrow(design))
# and seed = base_seed + row index. Because `rep` varies slowest, the first
# `reps` replicates of a run with MORE replicates get the same seeds, so with
# the same design and base_seed this regenerates the first `reps` datasets of
# the original run, one-to-one.
run_positive_control <- function(design, reps, stan_file, base_seed,
                                 proxy_cor = c(1, 0.7), proxy_seed_offset = 1e6,
                                 parallel = TRUE, workers = NULL, fit_args = list()) {
  tasks <- tidyr::expand_grid(rep = seq_len(reps), cell = seq_len(nrow(design)))
  tasks$seed <- base_seed + seq_len(nrow(tasks))

  run_one <- function(rep, cell, seed) {
    cfg      <- design[cell, , drop = FALSE]
    stan_mod <- cmdstanr::cmdstan_model(stan_file)   # cached compile; furrr-safe
    beta_conc <- if (!is.null(cfg$p10_beta_conc) && !is.na(cfg$p10_beta_conc)) cfg$p10_beta_conc else NULL
    # identical call to run_pilot()'s run_one(), so the dataset is identical
    sim <- simulate_fp(nsite = cfg$nsite, K = cfg$K, psi = cfg$psi, p11 = cfg$p11,
                       p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
                       sigma_p10     = if (!is.null(cfg$sigma_p10))   cfg$sigma_p10   else 0,
                       p10_beta_conc = beta_conc,
                       conf_effect   = if (!is.null(cfg$conf_effect)) cfg$conf_effect else 0,
                       conf_cor      = if (!is.null(cfg$conf_cor))    cfg$conf_cor    else 0,
                       seed = seed)
    # proxy noise drawn AFTER and on its own seed: never perturbs the dataset
    set.seed(seed + proxy_seed_offset)
    e <- stats::rnorm(length(sim$w))
    message(sprintf("[rep %d | cell %d]  p10=%.2f  cov=%.2f", rep, cell,
                    cfg$p10, cfg$verified_coverage))
    purrr::map(proxy_cor, function(r) {
      W <- r * sim$w + sqrt(1 - r^2) * e
      cbind(rep = rep, cell = cell, seed = seed, proxy_cor = r,
            verified_coverage = cfg$verified_coverage,
            do.call(fit_fpcov, c(list(sim = sim, W = W, stan_mod = stan_mod,
                                      seed = seed), fit_args)))
    }) |> purrr::list_rbind()
  }

  if (parallel) {
    nw <- if (is.null(workers)) max(1L, future::availableCores() - 1L) else workers
    future::plan(future::multisession, workers = nw)
    on.exit(future::plan(future::sequential), add = TRUE)
    rows <- furrr::future_pmap(tasks, run_one,
                               .options = furrr::furrr_options(seed = TRUE))
  } else {
    rows <- purrr::pmap(tasks, run_one)
  }
  purrr::list_rbind(rows)
}


# -----------------------------------------------------------------------------
# 3. PAIRING with the constant-p10 fits + SUMMARY
# -----------------------------------------------------------------------------
# res_const: data/fp_sim_results.rds (01_run_simulation.R). Its confusion rows
# come from the run with base_seed = 5000, indexed by (rep, cell) within that
# run. n_verified_sites and true_p10_marginal are realized quantities of the
# dataset, so matching them is the check that the datasets really are the same.
pair_with_constant <- function(res_pc, res_const) {
  const <- res_const |>
    dplyr::filter(.data$true_conf_effect > 0, .data$rep <= max(res_pc$rep)) |>
    dplyr::select(rep, cell,
                  const_n_verified_sites = n_verified_sites,
                  const_p10_marginal     = true_p10_marginal,
                  const_b1_est = stan_b1_est, const_b1_cov = stan_b1_cov,
                  const_p10_est = stan_p10_est, const_p10_cov = stan_p10_cov)
  out <- dplyr::left_join(res_pc, const, by = c("rep", "cell"))
  same <- out$n_verified_sites == out$const_n_verified_sites &
          abs(out$true_p10_marginal - out$const_p10_marginal) < 1e-12
  same <- !is.na(same) & same                       # unmatched rows count as mismatches
  if (!all(same))
    stop(sprintf(paste0("%d of %d rows do not match the original datasets ",
                        "(different design order, seeds, R version or RNG kind?)."),
                 sum(!same), length(same)))
  out
}

summarise_positive_control <- function(paired) {
  paired |>
    dplyr::mutate(fpcov_conv = .data$fpcov_ndiv == 0 & .data$fpcov_max_rhat < 1.01) |>
    dplyr::group_by(p10 = .data$true_p10, coverage = .data$verified_coverage,
                    proxy_cor = .data$proxy_cor) |>
    dplyr::summarise(
      n_reps            = dplyr::n(),
      fpcov_fail        = mean(!.data$fpcov_ok),
      fpcov_conv_rate   = mean(.data$fpcov_conv, na.rm = TRUE),
      W_cor_w           = mean(.data$W_cor_w),
      # occupancy slope: constant vs correctly specified, same datasets
      const_b1_cov95    = mean(.data$const_b1_cov, na.rm = TRUE),
      fpcov_b1_cov95    = mean(.data$fpcov_b1_cov, na.rm = TRUE),
      fpcov_b1_cov_mcse = sqrt(fpcov_b1_cov95 * (1 - fpcov_b1_cov95) / dplyr::n()),
      const_b1_bias     = mean(.data$const_b1_est - .data$true_b1, na.rm = TRUE),
      fpcov_b1_bias     = mean(.data$fpcov_b1_est - .data$true_b1, na.rm = TRUE),
      # false-positive part
      const_p10_cov95   = mean(.data$const_p10_cov, na.rm = TRUE),
      fpcov_p10_cov95   = mean(.data$fpcov_p10_cov, na.rm = TRUE),
      fpcov_g1_cov95    = mean(.data$fpcov_g1_cov, na.rm = TRUE),   # vs conf_effect; read only at proxy_cor = 1
      fpcov_g1_est      = mean(.data$fpcov_g1_est, na.rm = TRUE),
      fpcov_secs_per_fit = mean(.data$fpcov_runtime, na.rm = TRUE),
      .groups = "drop")
}
