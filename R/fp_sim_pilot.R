# =============================================================================
# fp_sim_pilot.R  —  pilot simulator + head-to-head fitter
# Bayesian false-positive occupancy model (JAV-03737 software note)
# -----------------------------------------------------------------------------
# Driver written with purrr (sequential) and furrr (parallel); no base-R
# for-loops. simulate_fp()/fit_both() are vectorized internally (better than
# mapping Bernoulli draws one by one). Uses ::-qualified calls, so the file
# sources with only base R present; each function errors only if its package
# is missing when actually called.
#
# Functions:
#   simulate_fp()     one synthetic dataset from KNOWN parameters, in the exact
#                     shape fp_occupancy.stan expects, PLUS the occuFP frame,
#                     PLUS the truth for scoring.
#   fit_both()        fit the Stan FP model (cmdstanr) and unmarked::occuFP to
#                     the same dataset; return ONE row of estimates, 95%
#                     coverage, convergence/degeneracy flags and runtimes.
#   run_pilot()       purrr::pmap (or furrr::future_pmap) over reps x cells.
#   summarise_pilot() dplyr group_by/summarise -> per-cell convergence, bias,
#                     coverage, runtime.
#
# GENERATING MODEL (mirrors fp_occupancy.stan):
#   z_i ~ Bernoulli(psi_i),  logit(psi_i) = b0 + b1 * x_occ_i            (occupancy)
#   automated occasion (Method 2):  y ~ Bernoulli( z*p11 + (1-z)*p10 )
#        logit(p11) = a0 + a_bio*bio + a_aci*aci + u[recorder]      (true detection)
#        p10 = constant false-positive probability                  <-- the estimand
#   verified occasion (Method 1, CERTAIN): y ~ Bernoulli( z*r11 ), no false pos.
#
# APPLES-TO-APPLES vs occuFP: DEFAULTS turn OFF detection covariates and the
# recorder random effect (a_bio = a_aci = 0, sig_u = 0), because occuFP cannot
# fit a random effect. Both models then target exactly {psi, p11, p10, r11}.
# Turn a_bio/a_aci/sig_u ON later to show the Stan model's added flexibility.
#
# occuFP mapping (confirmed against the CRAN reference for occuFP):
#   type = c(n_verified, K, 0)   -> first n_verified cols Method 1 (certain, no
#                                   false positives), next K Method 2 (FP).
#   stateformula = ~ xs  -> psi   |  detformula = ~ method -> auto<->p11, certain<->r11
#   FPformula = ~ 1      -> p10   |  Bformula   = ~ 1 (type-3 only; unused here)
# =============================================================================


# -----------------------------------------------------------------------------
# 1. SIMULATOR  (vectorized; no map needed inside)
# -----------------------------------------------------------------------------
simulate_fp <- function(nsite            = 500,   # occupancy sites (site-nights)
                        K                = 40,    # automated occasions per site
                        psi              = 0.5,   # occupancy at mean covariate (xs = 0)
                        b1               = -0.8,  # occupancy slope on standardized x
                        p11              = 0.6,   # automated TRUE-detection probability
                        p10              = 0.05,  # automated FALSE-positive prob (mean)  <-- key
                        sigma_p10        = 0,     # among-site SD of logit(p10); 0 = homogeneous (unstructured, logit-normal)
                        p10_beta_conc    = NULL,  # Tessa (i): draw p10_i ~ Beta(mean p10, concentration); small = aggregated
                        conf_effect      = 0,     # Tessa (ii): slope of logit(p10) on a latent "confusion species" gradient w
                        conf_cor         = 0,     # correlation of that gradient w with the occupancy covariate xs
                        r11              = 0.6,   # verified (certain) detection probability
                        verified_coverage = 0.30, # fraction of sites that get verified clips
                        n_verified       = 3,     # verified occasions per verified site
                        a_bio            = 0,     # detection covariate effect (OFF by default)
                        a_aci            = 0,     # detection covariate effect (OFF by default)
                        sig_u            = 0,     # recorder random-effect SD (OFF by default)
                        nobser           = 5,     # number of recorders
                        seed             = NULL) {

  if (!is.null(seed)) set.seed(seed)
  b0 <- qlogis(psi)
  a0 <- qlogis(p11)

  ## --- latent occupancy state ---
  x_occ <- rnorm(nsite)
  xs    <- as.numeric(scale(x_occ))                 # standardized; true slope = b1 exactly
  z     <- rbinom(nsite, 1, plogis(b0 + b1 * xs))
  X     <- cbind(1, xs)                             # Kbeta = 2, matches Stan design matrix

  ## --- recorder assignment + random effect ---
  obser <- sample(seq_len(nobser), nsite, replace = TRUE)
  u     <- rnorm(nobser, 0, sig_u)                  # all 0 when sig_u = 0

  ## --- automated (Method 2) occasions:  M x K matrix ---
  BIO  <- matrix(rnorm(nsite * K), nsite, K)
  ACI  <- matrix(rnorm(nsite * K), nsite, K)
  bios <- (BIO - mean(BIO)) / sd(BIO)               # standardize globally, like the qmd
  acis <- (ACI - mean(ACI)) / sd(ACI)
  P11  <- plogis(a0 + a_bio * bios + a_aci * acis + u[obser])  # u[obser] recycles down columns
  # Per-site false-positive rate. The fitted Stan model assumes a SINGLE p10, so any
  # among-site variation here is a controlled model MISSPECIFICATION the pilot can probe.
  #  (0) homogeneous               : p10_i = p10                              (default)
  #  (1) UNSTRUCTURED logit-normal : logit(p10_i) = logit(p10) + N(0, sigma_p10)
  #  (1) UNSTRUCTURED Beta (Tessa i): p10_i ~ Beta(p10*conc, (1-p10)*conc); small conc
  #      -> aggregated toward 0/1 ("p10 = 1 at some sites, 0 at others"). Damages p10 only.
  #  (2) STRUCTURED "confusion species" (Tessa ii): logit(p10_i) += conf_effect * w_i,
  #      where w is a SECOND latent gradient correlated (conf_cor) with the occupancy
  #      covariate xs but NOT in the model. It leaks into psi ~ xs, so the occupancy
  #      slope b1 becomes a blend of the target's and the soundalike's habitat.
  clampl <- function(p) qlogis(pmin(pmax(p, 1e-6), 1 - 1e-6))
  if (!is.null(p10_beta_conc)) {                    # (1) Beta base
    p10_base <- rbeta(nsite, p10 * p10_beta_conc, (1 - p10) * p10_beta_conc)
  } else if (sigma_p10 > 0) {                        # (1) logit-normal base
    p10_base <- plogis(qlogis(p10) + rnorm(nsite, 0, sigma_p10))
  } else {                                           # (0) homogeneous, no RNG draw
    p10_base <- rep(p10, nsite)
  }
  if (conf_effect != 0) {                            # (2) structured confusion gradient
    w       <- conf_cor * xs + sqrt(1 - conf_cor^2) * rnorm(nsite)  # cor(w, xs) ~ conf_cor, var 1
    p10_vec <- plogis(clampl(p10_base) + conf_effect * w)
  } else {
    w       <- rep(0, nsite)
    p10_vec <- p10_base
  }
  zmat    <- matrix(z, nsite, K)                    # z[i] repeated across its row
  p10_mat <- matrix(p10_vec, nsite, K)              # p10_i recycled across the row
  Pdet    <- zmat * P11 + (1 - zmat) * p10_mat      # occupied -> p11 ; unoccupied -> p10_i
  Y2      <- matrix(rbinom(nsite * K, 1, Pdet), nsite, K)

  # long format for Stan (column-major flatten; indices kept consistent)
  y2     <- as.vector(Y2)
  site2  <- rep(seq_len(nsite), times = K)
  obser2 <- rep(obser, times = K)
  bio2   <- as.vector(bios)
  aci2   <- as.vector(acis)

  ## --- verified (Method 1) occasions: certain, no false positives ---
  verified_site <- rbinom(nsite, 1, verified_coverage) == 1
  M1 <- matrix(NA_integer_, nsite, n_verified)      # NA where a site was not verified
  if (any(verified_site)) {
    nv <- sum(verified_site)
    zi <- z[verified_site]
    pv <- ifelse(zi == 1, r11, 0)                   # certain method: 0 at unoccupied sites
    M1[verified_site, ] <- matrix(
      rbinom(nv * n_verified, 1, matrix(pv, nv, n_verified)), nv, n_verified)
  }

  # Stan long format: only realized (non-NA) verified occasions
  y1_full <- as.vector(M1)
  s1_full <- rep(seq_len(nsite), times = n_verified)
  keep    <- !is.na(y1_full)
  y1      <- as.integer(y1_full[keep])
  site1   <- as.integer(s1_full[keep])

  # known_present[i] = 1 if any verified detection at site i
  known_present <- rep(0L, nsite)
  if (length(y1) > 0) {
    det_ver <- tapply(y1, site1, function(v) as.integer(any(v == 1)))
    known_present[as.integer(names(det_ver))] <- as.integer(det_ver)
  }

  ## --- Stan data list (exact fp_occupancy.stan data block) ---
  stan_data <- list(
    nsite = nsite, Kbeta = ncol(X), X = X, nobser = nobser,
    N2 = length(y2), y2 = as.integer(y2), site2 = as.integer(site2),
    obser2 = as.integer(obser2), bio2 = bio2, aci2 = aci2,
    N1 = length(y1), y1 = y1, site1 = site1,
    estimate_fp = 1L, estimate_re = as.integer(sig_u > 0), known_present = known_present
  )

  ## --- pieces for unmarked::occuFP ---
  y_umf <- cbind(M1, Y2)                            # first n_verified cols = Method 1, next K = Method 2
  method_col <- c(rep("certain", n_verified), rep("auto", K))
  obsCovs  <- data.frame(method = factor(rep(method_col, times = nsite),
                                         levels = c("auto", "certain")))  # auto = reference
  siteCovs <- data.frame(xs = xs)

  list(
    stan_data = stan_data,
    umf   = list(y = y_umf, siteCovs = siteCovs, obsCovs = obsCovs,
                 type = c(n_verified, K, 0)),
    truth = list(psi = psi, b0 = b0, b1 = b1, p11 = p11, p10 = p10, r11 = r11,
                 p10_marginal = mean(p10_vec), sigma_p10 = sigma_p10,
                 p10_beta_conc = if (is.null(p10_beta_conc)) NA_real_ else p10_beta_conc,
                 conf_effect = conf_effect, conf_cor = conf_cor,
                 conf_cor_realized = if (conf_effect != 0) as.numeric(cor(w, xs)) else NA_real_,
                 a_bio = a_bio, a_aci = a_aci, sig_u = sig_u),
    design = list(nsite = nsite, K = K, verified_coverage = verified_coverage,
                  n_verified = n_verified, n_verified_sites = sum(verified_site))
  )
}


# -----------------------------------------------------------------------------
# 2. FITTER  (Stan FP model  +  unmarked::occuFP  on the same dataset)
# -----------------------------------------------------------------------------
fit_both <- function(sim, stan_mod,
                     chains = 4, iter_warmup = 500, iter_sampling = 500,
                     adapt_delta = 0.9, seed = 1, parallel_chains = chains,
                     verbose = FALSE) {

  tr <- sim$truth
  q  <- function(v, p) unname(stats::quantile(v, p))
  in95 <- function(true, v) as.logical(true >= q(v, .025) & true <= q(v, .975))
  # Under site-varying p10 the constant-p10 model targets the MARGINAL mean FP rate,
  # so score p10 against that (identical to the nominal p10 when homogeneous).
  p10_bench <- if (!is.null(tr$p10_marginal)) tr$p10_marginal else tr$p10

  ## ---------- (a) Stan false-positive model ----------
  stan_res <- tryCatch({
    fit <- stan_mod$sample(data = sim$stan_data, chains = chains,
                           parallel_chains = parallel_chains,
                           iter_warmup = iter_warmup, iter_sampling = iter_sampling,
                           adapt_delta = adapt_delta, seed = seed,
                           refresh = if (verbose) 200 else 0)
    ds   <- fit$diagnostic_summary(quiet = TRUE)
    smry <- fit$summary(c("beta", "p10", "p11_ref", "r11", "sigma_u"))
    dr   <- fit$draws(variables = c("beta", "p10", "p11_ref", "r11", "sigma_u"),
                      format = "df")
    psi_hat <- plogis(dr$`beta[1]`)                 # occupancy at xs = 0 -> compares to psi
    list(ok = TRUE,
         max_rhat = max(smry$rhat, na.rm = TRUE),
         min_ess  = min(smry$ess_bulk, na.rm = TRUE),
         ndiv     = sum(ds$num_divergent),
         runtime  = as.numeric(fit$time()$total),
         psi_est = mean(psi_hat),      psi_cov = in95(tr$psi, psi_hat),
         p10_est = mean(dr$p10),       p10_cov = in95(p10_bench, dr$p10),
         p10_lo  = q(dr$p10, .025),    p10_hi  = q(dr$p10, .975),
         p11_est = mean(dr$p11_ref),   p11_cov = in95(tr$p11, dr$p11_ref),
         b1_est  = mean(dr$`beta[2]`), b1_cov  = in95(tr$b1,  dr$`beta[2]`),
         b1_lo   = q(dr$`beta[2]`, .025), b1_hi = q(dr$`beta[2]`, .975))
  }, error = function(e) list(ok = FALSE, msg = conditionMessage(e)))

  ## ---------- (b) unmarked::occuFP ----------
  # Now captures Wald 95% CIs and coverage flags for p10, psi, and the occupancy
  # slope b1, so the head-to-head is coverage-vs-coverage, not just point bias.
  # CIs come back NaN when the Hessian is singular (the degenerate boundary fits),
  # which correctly leaves occuFP coverage UNDEFINED there: it is then scored only
  # over the fits that actually produced a finite interval.
  occufp_res <- tryCatch({
    umf <- unmarked::unmarkedFrameOccuFP(
      y = sim$umf$y, siteCovs = sim$umf$siteCovs,
      obsCovs = sim$umf$obsCovs, type = sim$umf$type)
    t0 <- proc.time()[["elapsed"]]
    m  <- unmarked::occuFP(detformula = ~ method, FPformula = ~ 1,
                           Bformula = ~ 1, stateformula = ~ xs, data = umf)
    rt <- proc.time()[["elapsed"]] - t0

    se       <- tryCatch(unmarked::SE(m), error = function(e) NA_real_)
    cf_all   <- coef(m)
    conv     <- tryCatch(m@opt$convergence, error = function(e) NA_integer_)
    bad_se   <- any(!is.finite(se))                 # singular Hessian -> NaN/Inf SEs
    boundary <- any(abs(cf_all) > 10)               # estimates run to the boundary
    degen    <- bad_se || boundary || (!is.na(conv) && conv != 0)

    # Wald 95% CI on the link scale for one row of a submodel; NA if it cannot be formed.
    # Bare confint() dispatches to unmarked's S4 method (as coef(m) does above); the
    # Wald interval is estimate +/- qnorm * SE, so it returns NaN (not an error) when SE
    # is non-finite, i.e. the singular-Hessian boundary fits.
    ci <- function(type, row) tryCatch(
      suppressWarnings(unname(confint(m, type = type, level = 0.95)[row, ])),
      error = function(e) c(NA_real_, NA_real_))
    ci_state_int <- ci("state", 1)                  # logit(psi) at xs = 0
    ci_state_slp <- ci("state", 2)                  # b1 (occupancy slope); link scale = Stan beta[2]
    ci_fp_int    <- ci("fp", 1)                     # logit(p10)

    psi_lo <- plogis(ci_state_int[1]); psi_hi <- plogis(ci_state_int[2])
    p10_lo <- plogis(ci_fp_int[1]);    p10_hi <- plogis(ci_fp_int[2])
    b1_est <- unname(coef(m, type = "state")[2])
    b1_lo  <- ci_state_slp[1];         b1_hi  <- ci_state_slp[2]

    inCI <- function(true, lo, hi) if (is.finite(lo) && is.finite(hi))
      as.logical(true >= lo & true <= hi) else NA
    list(ok = TRUE, degenerate = degen, convergence = conv,
         bad_se = bad_se, boundary = boundary, runtime = rt,
         psi_est = plogis(coef(m, type = "state")[1]),  # psi at xs = 0
         psi_lo = psi_lo, psi_hi = psi_hi, psi_cov = inCI(tr$psi, psi_lo, psi_hi),
         p10_est = plogis(coef(m, type = "fp")[1]),     # false-positive prob
         p10_lo = p10_lo, p10_hi = p10_hi, p10_cov = inCI(p10_bench, p10_lo, p10_hi),
         p11_est = plogis(coef(m, type = "det")[1]),    # p11 (reference level = auto)
         b1_est = b1_est, b1_lo = b1_lo, b1_hi = b1_hi, b1_cov = inCI(tr$b1, b1_lo, b1_hi))
  }, error = function(e) list(ok = FALSE, degenerate = TRUE, msg = conditionMessage(e)))

  ## ---------- one stacked row ----------
  g <- function(x, f, default = NA) if (isTRUE(x$ok)) x[[f]] else default
  data.frame(
    nsite = sim$design$nsite, K = sim$design$K,
    verified_coverage = sim$design$verified_coverage,
    n_verified_sites  = sim$design$n_verified_sites,
    true_p10 = tr$p10, true_p10_marginal = p10_bench,
    true_sigma_p10 = if (is.null(tr$sigma_p10)) 0 else tr$sigma_p10,
    true_beta_conc = if (is.null(tr$p10_beta_conc) || is.na(tr$p10_beta_conc)) 0 else tr$p10_beta_conc,
    true_conf_effect = if (is.null(tr$conf_effect)) 0 else tr$conf_effect,
    true_conf_cor    = if (is.null(tr$conf_cor)) 0 else tr$conf_cor,
    true_b1 = tr$b1, true_psi = tr$psi, true_p11 = tr$p11,
    # ----- Stan FP model -----
    stan_ok        = isTRUE(stan_res$ok),
    stan_max_rhat  = g(stan_res, "max_rhat"),
    stan_ndiv      = g(stan_res, "ndiv"),
    stan_runtime   = g(stan_res, "runtime"),
    stan_p10_est   = g(stan_res, "p10_est"),  stan_p10_cov = g(stan_res, "p10_cov"),
    stan_p10_lo    = g(stan_res, "p10_lo"),   stan_p10_hi  = g(stan_res, "p10_hi"),
    stan_psi_est   = g(stan_res, "psi_est"),  stan_psi_cov = g(stan_res, "psi_cov"),
    stan_b1_est    = g(stan_res, "b1_est"),   stan_b1_cov  = g(stan_res, "b1_cov"),
    stan_b1_lo     = g(stan_res, "b1_lo"),    stan_b1_hi   = g(stan_res, "b1_hi"),
    stan_p11_est   = g(stan_res, "p11_est"),
    # ----- unmarked::occuFP -----
    occufp_ok         = isTRUE(occufp_res$ok),
    occufp_degenerate = isTRUE(occufp_res$degenerate),
    occufp_runtime    = g(occufp_res, "runtime"),
    occufp_p10_est    = g(occufp_res, "p10_est"),
    occufp_p10_lo     = g(occufp_res, "p10_lo"),  occufp_p10_hi = g(occufp_res, "p10_hi"),
    occufp_p10_cov    = g(occufp_res, "p10_cov"),
    occufp_psi_est    = g(occufp_res, "psi_est"),
    occufp_psi_lo     = g(occufp_res, "psi_lo"),  occufp_psi_hi = g(occufp_res, "psi_hi"),
    occufp_psi_cov    = g(occufp_res, "psi_cov"),
    occufp_b1_est     = g(occufp_res, "b1_est"),
    occufp_b1_lo      = g(occufp_res, "b1_lo"),   occufp_b1_hi  = g(occufp_res, "b1_hi"),
    occufp_b1_cov     = g(occufp_res, "b1_cov"),
    occufp_p11_est    = g(occufp_res, "p11_est"),
    stringsAsFactors = FALSE
  )
}


# -----------------------------------------------------------------------------
# 3. DRIVER (purrr / furrr) + SUMMARY (dplyr)
# -----------------------------------------------------------------------------
# Sequential:  run_pilot(design, reps = 10)
# Parallel:    run_pilot(design, reps = 10, parallel = TRUE, workers = 6,
#                        fit_args = list(parallel_chains = 1))
#   -> furrr::future_pmap over reps x cells. Set parallel_chains = 1 so each
#      Stan fit runs its chains SERIALLY: keep workers x chains <= cores, or the
#      outer workers and cmdstanr's own chain-parallelism fight over cores.
#   -> The model is (re)built INSIDE each task via cmdstan_model(stan_file): the
#      compiled binary is cached (no recompile), and a CmdStanModel's external
#      pointer does NOT survive being shipped to a furrr worker, so we must not
#      close over a pre-built object.
run_pilot <- function(design, reps = 10, stan_file = "fp_occupancy.stan",
                      base_seed = 1000, parallel = FALSE, workers = NULL,
                      fit_args = list()) {

  # task grid: one row per (rep, cell), each with its own seed
  tasks <- tidyr::expand_grid(rep = seq_len(reps), cell = seq_len(nrow(design)))
  tasks$seed <- base_seed + seq_len(nrow(tasks))

  run_one <- function(rep, cell, seed) {
    cfg      <- design[cell, , drop = FALSE]
    stan_mod <- cmdstanr::cmdstan_model(stan_file)   # cached compile; furrr-safe
    beta_conc <- if (!is.null(cfg$p10_beta_conc) && !is.na(cfg$p10_beta_conc)) cfg$p10_beta_conc else NULL
    sim <- simulate_fp(nsite = cfg$nsite, K = cfg$K, psi = cfg$psi, p11 = cfg$p11,
                       p10 = cfg$p10, verified_coverage = cfg$verified_coverage,
                       sigma_p10     = if (!is.null(cfg$sigma_p10))   cfg$sigma_p10   else 0,
                       p10_beta_conc = beta_conc,
                       conf_effect   = if (!is.null(cfg$conf_effect)) cfg$conf_effect else 0,
                       conf_cor      = if (!is.null(cfg$conf_cor))    cfg$conf_cor    else 0,
                       seed = seed)
    message(sprintf("[rep %d | cell %d]  p10=%.2f  sigma_p10=%.2f  conf=%.2f  cov=%.2f  nsite=%d",
                    rep, cell, cfg$p10,
                    if (!is.null(cfg$sigma_p10)) cfg$sigma_p10 else 0,
                    if (!is.null(cfg$conf_effect)) cfg$conf_effect else 0,
                    cfg$verified_coverage, cfg$nsite))
    cbind(rep = rep, cell = cell,
          do.call(fit_both, c(list(sim = sim, stan_mod = stan_mod), fit_args)))
  }

  if (parallel) {
    if (!requireNamespace("furrr", quietly = TRUE) ||
        !requireNamespace("future", quietly = TRUE))
      stop("parallel = TRUE needs the 'furrr' and 'future' packages.")
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

summarise_pilot <- function(res) {
  if (!"true_beta_conc" %in% names(res)) res$true_beta_conc <- 0  # compat com res de rodada antiga
  # compat: rodadas antigas nao tem as colunas de IC/cobertura do occuFP
  for (nm in c("occufp_p10_cov", "occufp_b1_cov", "occufp_b1_est"))
    if (!nm %in% names(res)) res[[nm]] <- NA
  res |>
    dplyr::mutate(
      stan_converged  = as.numeric(.data$stan_ndiv == 0 & .data$stan_max_rhat < 1.01),
      occufp_failed   = as.numeric(.data$occufp_degenerate),
      stan_p10_bias   = .data$stan_p10_est   - .data$true_p10_marginal,
      # occuFP bias scored only over CONVERGED fits: the boundary fits push estimates to
      # 0/1 and would otherwise poison the mean. Mask to NA where degenerate (matches coverage).
      occufp_p10_bias = ifelse(.data$occufp_degenerate, NA_real_, .data$occufp_p10_est - .data$true_p10_marginal),
      occufp_b1_bias  = ifelse(.data$occufp_degenerate, NA_real_, .data$occufp_b1_est  - .data$true_b1),
      stan_p10_cov_n  = as.numeric(.data$stan_p10_cov),
      stan_b1_bias    = .data$stan_b1_est - .data$true_b1,   # occupancy slope: the structured-mode damage
      stan_b1_cov_n   = as.numeric(.data$stan_b1_cov),
      occufp_p10_cov_n = as.numeric(.data$occufp_p10_cov),   # coverage over CONVERGED fits (NA elsewhere)
      occufp_b1_cov_n  = as.numeric(.data$occufp_b1_cov)
    ) |>
    dplyr::group_by(p10 = .data$true_p10, coverage = .data$verified_coverage,
                    sigma_p10 = .data$true_sigma_p10, beta_conc = .data$true_beta_conc,
                    conf_effect = .data$true_conf_effect, conf_cor = .data$true_conf_cor) |>
    dplyr::summarise(
      stan_conv_rate      = mean(.data$stan_converged,  na.rm = TRUE),
      occufp_fail_rate    = mean(.data$occufp_failed,   na.rm = TRUE),
      stan_p10_coverage95 = mean(.data$stan_p10_cov_n,  na.rm = TRUE),
      stan_p10_bias       = mean(.data$stan_p10_bias,   na.rm = TRUE),
      stan_b1_coverage95  = mean(.data$stan_b1_cov_n,   na.rm = TRUE),  # falls under structured p10
      stan_b1_bias        = mean(.data$stan_b1_bias,    na.rm = TRUE),
      occufp_p10_coverage95 = mean(.data$occufp_p10_cov_n, na.rm = TRUE),  # head-to-head vs Stan
      occufp_b1_coverage95  = mean(.data$occufp_b1_cov_n,  na.rm = TRUE),
      occufp_p10_bias     = mean(.data$occufp_p10_bias, na.rm = TRUE),
      occufp_b1_bias      = mean(.data$occufp_b1_bias,  na.rm = TRUE),
      stan_secs_per_fit   = mean(.data$stan_runtime,    na.rm = TRUE),
      occufp_secs_per_fit = mean(.data$occufp_runtime,  na.rm = TRUE),
      .groups = "drop"
    )
}

# -----------------------------------------------------------------------------
# plot_pilot(): visualização rápida do resumo (4 painéis).  requer ggplot2 + patchwork
#   occuFP falha e Stan converge  |  cobertura 95% de p10 (dano do NÃO estruturado)
#   e de b1 (dano do ESTRUTURADO). Cada ponto é uma célula do desenho, colorida pelo
#   braço (baseline / Beta / logit-normal / confusão).
# -----------------------------------------------------------------------------
plot_pilot <- function(res) {
  s <- summarise_pilot(res) |>
    dplyr::mutate(
      arm  = dplyr::case_when(conf_effect != 0 ~ "confusion (structured)",
                              beta_conc   != 0 ~ "Beta (unstructured)",
                              sigma_p10   != 0 ~ "logit-normal (unstructured)",
                              TRUE             ~ "baseline"),
      cell = sprintf("p10 = %.2f | coverage = %.2f", p10, coverage))
  pnl <- function(x, title, ref = NULL) {
    g <- ggplot2::ggplot(s, ggplot2::aes(.data[[x]], cell, colour = arm))
    if (!is.null(ref))
      g <- g + ggplot2::geom_vline(xintercept = ref, linetype = 2, colour = "grey60")
    g + ggplot2::geom_point(size = 2.6,
                            position = ggplot2::position_dodge(width = 0.5)) +
      ggplot2::labs(x = NULL, y = NULL, colour = "Scenario", title = title) +
      ggplot2::xlim(0, 1) + ggplot2::theme_bw(base_size = 11)
  }
  patchwork::wrap_plots(
    pnl("occufp_fail_rate",    "occuFP failure rate"),
    pnl("stan_conv_rate",      "Stan convergence rate"),
    pnl("stan_p10_coverage95", "p10 coverage (95% CrI)", ref = 0.95),
    pnl("stan_b1_coverage95",  "b1 coverage (95% CrI)",  ref = 0.95),
    ncol = 2, guides = "collect")
}


# =============================================================================
# HOW TO RUN THE 10-REPLICATE PILOT
# =============================================================================
# Prereqs (once):
#   install.packages(c("purrr", "dplyr", "tidyr", "furrr", "future",
#                      "posterior", "unmarked"))
#   install.packages("cmdstanr", repos = c("https://stan-dev.r-universe.dev",
#                                           getOption("repos")))
#   cmdstanr::install_cmdstan()          # builds CmdStan; a few minutes, once
#   # put fp_occupancy.stan in the working directory (same folder as this file)
#
# Then:
#   library(cmdstanr); library(posterior); library(unmarked)
#   library(purrr); library(dplyr); library(tidyr)   # furrr/future only if parallel
#   source("fp_sim_pilot.R")
#
#   # ---- (0) smoke test: ONE dataset, confirm both models fit and the plumbing works
#   sm  <- cmdstanr::cmdstan_model("fp_occupancy.stan")
#   one <- simulate_fp(nsite = 300, K = 20, p10 = 0.10, verified_coverage = 0.30, seed = 1)
#   fit_both(one, sm, verbose = TRUE)     # inspect the single row before scaling up
#   # p10-heterogeneity smoke tests (Tessa's failure modes):
#   #   (i)  unstructured, Beta aggregation (small conc -> p10 near 0/1 across sites)
#   het_beta <- simulate_fp(nsite = 300, K = 20, p10 = 0.10, p10_beta_conc = 2,
#                           verified_coverage = 0.30, seed = 1)
#   #   (ii) structured "confusion species": p10 tracks a latent gradient correlated
#   #        with the occupancy covariate -> watch the occupancy slope b1, not just p10
#   het_conf <- simulate_fp(nsite = 300, K = 20, p10 = 0.10, conf_effect = 1.5,
#                           conf_cor = 0.7, verified_coverage = 0.30, seed = 1)
#   fit_both(het_beta, sm, verbose = TRUE); fit_both(het_conf, sm, verbose = TRUE)
#
#   # ---- (1) the pilot design. Keep the failure modes as SEPARATE arms (cleaner to
#   #      read than fully crossing them): a homogeneous baseline, an unstructured arm
#   #      (Beta aggregation, Tessa i), and a structured confusion arm (Tessa ii).
#   grid0 <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.10, 0.30),
#                               nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
#   pilot_design <- dplyr::bind_rows(
#     dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0,   conf_cor = 0),   # baseline
#     dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = 2,  conf_effect = 0,   conf_cor = 0),   # unstructured (Beta)
#     dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)) # confusion
#   #  12 cells x 10 reps = 120 fits  (small data -> seconds per fit)
#   #
#   #  OPTIONAL boundary arm (reproduces the real-data occuFP degeneracy): add a cell
#   #  with p10 near zero, where the frequentist MLE sits on the boundary and its
#   #  Hessian goes singular. The Stan model still returns a proper posterior there.
#   #    grid_edge <- tidyr::expand_grid(p10 = 0.01, verified_coverage = c(0.10, 0.30),
#   #                                    nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
#   #    pilot_design <- dplyr::bind_rows(pilot_design,
#   #      dplyr::mutate(grid_edge, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0))
#
#   # ---- (2a) run it sequentially (simplest; cmdstanr already uses 4 chains/fit)
#   res <- run_pilot(pilot_design, reps = 10)
#
#   # ---- (2b) OR in parallel across fits (best for the full study). Keep
#   #          workers x chains <= physical cores. On an M-series with ~10-14
#   #          cores, e.g. 6 workers x 1 chain each:
#   # res <- run_pilot(pilot_design, reps = 10, parallel = TRUE, workers = 6,
#   #                  fit_args = list(parallel_chains = 1))
#
#   saveRDS(res, "fp_sim_pilot_results.rds")
#
#   # ---- (3) read the story off the summary
#   summarise_pilot(res)
#
# WHAT TO LOOK FOR (this is what sizes the full study and de-risks the note):
#   * occufp_fail_rate  should CLIMB as p10 approaches the boundary (near 0), the
#     exact regime where occuFP degenerated on the real BirdNET.MaxPrecision cell;
#   * stan_conv_rate    should stay ~1 across all cells (Stan stays stable);
#   * stan_p10_coverage95 should sit near 0.95 (calibrated intervals);
#   * stan_p10_bias      ~0; occufp_p10_bias only over the fits that converged
#     (read it together with occufp_fail_rate);
#   * occufp_p10_coverage95 / occufp_b1_coverage95: the head-to-head. Over the fits
#     that DID converge, occuFP is biased under heterogeneity in the same direction
#     as Stan, so its Wald intervals also miss -- the point estimate simply gives
#     no warning, whereas the Bayesian interval does;
#   * *_secs_per_fit     per-fit cost -> multiply by (cells x reps x 2 models) to
#     size the real run.
#   * UNSTRUCTURED p10 (sigma_p10 > 0 or p10_beta_conc set, Tessa i): watch
#     stan_p10_bias grow and stan_p10_coverage95 drop below 0.95 -- this damages the
#     FALSE-POSITIVE estimate. The occupancy slope (stan_b1_*) should stay fine.
#   * STRUCTURED confusion p10 (conf_effect != 0, Tessa ii): the damage moves to the
#     OCCUPANCY slope -- watch stan_b1_coverage95 fall and stan_b1_bias grow while
#     p10 may still look ok. This is the "killer" case: the FP structure leaks into
#     the psi ~ covariate estimate (the blend of the two species' habitats).
#   * Both feed the note's limitations + recommendations ("how much heterogeneity,
#     and of which kind, is too much").
#
# NOTES / things the pilot is meant to confirm on your machine:
#   * occuFP must tolerate NA blocks in the type-1 columns for non-verified sites
#     (standard unmarked missing-data handling). If it ever errors on that, the
#     fallback is to give EVERY site n_verified clips and vary n_verified instead
#     of the fraction of sites -- a one-line change in simulate_fp().
#   * coverage = 0 is a Stan-ONLY identifiability probe (no certain detections ->
#     occuFP is not even defined); keep it out of the head-to-head.
#   * head-to-head defaults keep a_bio = a_aci = 0 and sig_u = 0 so both models
#     target the same parameters. A separate arm with sig_u > 0 shows the Stan
#     model fitting a recorder random effect that occuFP cannot.
# =============================================================================
