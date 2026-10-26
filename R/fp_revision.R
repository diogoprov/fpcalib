# =============================================================================
# fp_revision.R  —  checks added while revising the manuscript (October 2026)
# -----------------------------------------------------------------------------
# Refits datasets of 01_run_simulation.R with the crywolf package
# (https://provetelab.org/crywolf/), to answer three questions raised in the
# revision:
#   (1) what does modelling the false-positive rate on the occupancy covariate
#       (fp = ~ x) cost when the rate is in fact homogeneous?
#   (2) can a user detect structured confusion from the data, by LOO
#       (fp = ~ x against fp = ~ 1) or by a posterior predictive check?
#   (3) does a site random effect on the false-positive rate (random_fp) fix
#       the unstructured regime?
# The datasets are regenerated with simulate_fp() from R/fp_sim_pilot.R under
# the same seeds and random number generator as the original run, and
# checked against the stored results before any fit.
# =============================================================================

# designs of 01_run_simulation.R, in the same order, so that cell indices and
# seeds line up with the original run
revision_designs <- function() {
  grid0 <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.10, 0.30),
                              nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
  core <- dplyr::bind_rows(
    dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0),
    dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = 2, conf_effect = 0, conf_cor = 0),
    dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7))
  boundary <- tidyr::expand_grid(p10 = 0.01, verified_coverage = c(0.10, 0.30),
                                 nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
    dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0)
  cov_sweep <- tidyr::expand_grid(p10 = 0.05, verified_coverage = c(0, 0.05, 0.50),
                                  nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
    dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0)
  conf_sweep <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.50, 0.70, 0.90),
                                   nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
    dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)
  design <- dplyr::bind_rows(core, boundary, cov_sweep, conf_sweep)
  is_conf <- design$conf_effect > 0
  list(main = design[!is_conf, , drop = FALSE], conf = design[is_conf, , drop = FALSE])
}

# the tasks of run_pilot(): seed = base_seed + row of expand_grid(rep, cell)
revision_tasks <- function(design, reps, base_seed, run) {
  tasks <- tidyr::expand_grid(rep = seq_len(reps), cell = seq_len(nrow(design)))
  tasks$seed <- base_seed + seq_len(nrow(tasks))
  tasks$run <- run
  tasks
}

# one dataset of the original run; the original was simulated in furrr
# workers, which use the L'Ecuyer-CMRG generator
regenerate <- function(cfg, seed) {
  RNGkind("L'Ecuyer-CMRG")
  beta_conc <- if (!is.na(cfg$p10_beta_conc)) cfg$p10_beta_conc else NULL
  simulate_fp(nsite = cfg$nsite, K = cfg$K, psi = cfg$psi, p11 = cfg$p11,
              p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
              sigma_p10 = cfg$sigma_p10, p10_beta_conc = beta_conc,
              conf_effect = cfg$conf_effect, conf_cor = cfg$conf_cor, seed = seed)
}

# the dataset as a crywolf fp_data object (no recorder effect in these cells)
to_fp_data <- function(sim) {
  sd <- sim$stan_data
  withCallingHandlers(
    crywolf::fp_data(auto = data.frame(site = sd$site2, y = sd$y2),
                     sites = data.frame(site = seq_len(sd$nsite), x = sd$X[, 2]),
                     verified = if (sd$N1 > 0) data.frame(site = sd$site1, y = sd$y1)),
    crywolf_design_warning = function(w) invokeRestart("muffleWarning"))
}

# one model fitted to one dataset -> one row, with the pointwise LOO values
# in a list column (for paired model comparisons)
fit_revision <- function(d, sim, model, seed, iter = 1000) {
  tr <- sim$truth
  args <- switch(model,
    constant  = list(fp = ~ 1),
    fp_x      = list(fp = ~ x),
    random_fp = list(fp = ~ 1, random_fp = TRUE))
  t0 <- Sys.time()
  res <- tryCatch({
    m <- suppressWarnings(do.call(crywolf::fp_occu, c(list(
      d, occ = ~ x, random_recorder = FALSE, chains = 4, parallel_chains = 1,
      threads_per_chain = 1, iter_warmup = iter, iter_sampling = iter,
      adapt_delta = 0.95, seed = seed, refresh = 0, show_messages = FALSE), args)))
    s <- summary(m)$table
    row <- function(v) s[s$variable == v, ]
    l <- suppressWarnings(loo(m))
    list(ok = TRUE, m = m, b1 = row("occ_x"), p10 = row("p10_bar"),
         elpd_i = l$pointwise[, "elpd_loo"], k_high = sum(l$diagnostics$pareto_k > 0.7),
         ppc_p = suppressWarnings(crywolf::fp_ppc(m, ndraws = 500, seed = seed))$p_value)
  }, error = function(e) list(ok = FALSE, msg = conditionMessage(e)))
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  na <- NA_real_
  ok <- isTRUE(res$ok)
  out <- data.frame(
    model = model, ok = ok, msg = if (ok) NA_character_ else res$msg,
    true_b1 = tr$b1, true_p10_marginal = tr$p10_marginal,
    n_verified_sites = sim$design$n_verified_sites,
    b1_est = if (ok) res$b1$mean else na, b1_lo = if (ok) res$b1$lower else na,
    b1_hi = if (ok) res$b1$upper else na,
    p10_est = if (ok) res$p10$mean else na, p10_lo = if (ok) res$p10$lower else na,
    p10_hi = if (ok) res$p10$upper else na,
    max_rhat = if (ok) res$m$diagnostics$max_rhat else na,
    min_ess_bulk = if (ok) res$m$diagnostics$min_ess_bulk else na,
    ndiv = if (ok) res$m$diagnostics$divergences else na,
    elpd = if (ok) sum(res$elpd_i) else na, k_high = if (ok) res$k_high else na,
    ppc_p = if (ok) res$ppc_p else na, seconds = secs)
  out$elpd_i <- list(if (ok) res$elpd_i else NULL)
  out
}

# which models each regime gets
revision_models <- function(cfg) {
  if (cfg$conf_effect > 0) c("constant", "fp_x")
  else if (!is.na(cfg$p10_beta_conc)) c("constant", "random_fp")
  else c("constant", "fp_x")
}

# all the models of one task, on one regenerated dataset
run_revision_task <- function(design, rep, cell, seed, run) {
  cfg <- design[[run]][cell, , drop = FALSE]
  sim <- regenerate(cfg, seed)
  d <- to_fp_data(sim)
  rows <- purrr::map(revision_models(cfg), function(mod) fit_revision(d, sim, mod, seed))
  cbind(run = run, rep = rep, cell = cell, seed = seed,
        p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
        regime = if (cfg$conf_effect > 0) "structured"
                 else if (!is.na(cfg$p10_beta_conc)) "unstructured" else "homogeneous",
        purrr::list_rbind(rows))
}

# regenerated datasets against the stored results of 01_run_simulation.R
check_regeneration <- function(tasks, design, res_orig) {
  purrr::pmap_lgl(tasks, function(rep, cell, seed, run) {
    cfg <- design[[run]][cell, , drop = FALSE]
    sim <- regenerate(cfg, seed)
    o <- res_orig[res_orig$rep == rep & res_orig$cell == cell &
                    (res_orig$true_conf_effect > 0) == (run == "conf"), ]
    nrow(o) == 1 && o$n_verified_sites == sim$design$n_verified_sites &&
      isTRUE(all.equal(o$true_p10_marginal, sim$truth$p10_marginal))
  })
}
