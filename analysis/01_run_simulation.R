# =============================================================================
# 01_run_simulation.R
# Reproduce the calibration study: 23 cells x 2 models. The CONFUSION arm
# (10 cells: 2 p10 x 5 verification levels, 0.10 to 0.90) runs at MORE
# replicates than the other 13 cells, because those cells carry the paper's
# take-home (coverage of the occupancy slope under structured confusion) and
# need a tighter Monte Carlo SE on that coverage.
# Run with the COMPENDIUM ROOT as the working directory.
#
# On an 18-core machine (16 workers) this is ~13 h ideal at reps_confusion =
# 300 (median ~171 s per Stan fit at adapt_delta = 0.95). Set reps_confusion
# to 200 for ~10 h, or lower both reps for a quick check first.
# =============================================================================
library(cmdstanr); library(posterior); library(unmarked)
library(purrr); library(dplyr); library(tidyr); library(furrr); library(future)

source("R/fp_sim_pilot.R")

# Absolute path so the furrr workers (separate R processes) resolve the model
# regardless of their working directory.
# RE toggle: drops the recorder random effect from the likelihood when the data
# were generated without one (sig_u = 0), which removes the sigma_u -> 0 funnel
# that produced the residual divergences. estimate_re is set inside simulate_fp()
# as as.integer(sig_u > 0), so head-to-head cells fit without the RE and any
# future sig_u > 0 arm fits with it.
stan_file <- normalizePath(file.path("inst", "stan", "fp_occupancy_re_toggle.stan"))

# --- CORE design: 3 regimes x 2 p10 x 2 verification coverage = 12 cells -----
grid0 <- tidyr::expand_grid(p10 = c(0.05, 0.20),
                            verified_coverage = c(0.10, 0.30),
                            nsite = 300, K = 20, psi = 0.5, p11 = 0.6)
core <- dplyr::bind_rows(
  dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0,   conf_cor = 0),   # homogeneous
  dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = 2,  conf_effect = 0,   conf_cor = 0),   # unstructured (Beta)
  dplyr::mutate(grid0, sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)) # structured confusion

# --- BOUNDARY cells: p10 ~ 0 (homogeneous) reproduce the occuFP degeneracy -----
#     seen on the real Max Precision data: the frequentist MLE runs onto the
#     boundary and its Hessian goes singular, while Stan still returns a proper
#     posterior. 2 cells.
boundary <- tidyr::expand_grid(p10 = 0.01, verified_coverage = c(0.10, 0.30),
                               nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0)

# --- COVERAGE sweep at the reference (p10 = 0.05, homogeneous) for the
#     "how much to verify" guideline. 0.10 and 0.30 already sit in `core`, so
#     add 0, 0.05, 0.50. coverage = 0 is a Stan-only identifiability probe: with
#     no verified clips p10 is unanchored, so occuFP is undefined there and
#     Stan's p10 is expected to be wide (it shows verification is necessary). 3 cells.
cov_sweep <- tidyr::expand_grid(p10 = 0.05, verified_coverage = c(0, 0.05, 0.50),
                                nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 0, conf_cor = 0)

# --- CONFUSION x verification sweep: answers Clare et al. (2021) head-on ------
#     Clare reported that the correction stays nearly unbiased once ENOUGH is
#     verified. Under structured confusion our core cells (10%, 30%) show no
#     recovery; here we push verification high (50, 70, 90%) at both p10 levels
#     to see whether the environmental-effect coverage recovers, as Clare's
#     abundance results suggest, or stays collapsed (an occupancy-specific
#     refinement). 6 cells.
conf_sweep <- tidyr::expand_grid(p10 = c(0.05, 0.20), verified_coverage = c(0.50, 0.70, 0.90),
                                 nsite = 300, K = 20, psi = 0.5, p11 = 0.6) |>
  dplyr::mutate(sigma_p10 = 0, p10_beta_conc = NA, conf_effect = 1.5, conf_cor = 0.7)

design <- dplyr::bind_rows(core, boundary, cov_sweep, conf_sweep)  # 12 + 2 + 3 + 6 = 23 cells
# Slice the results later by parameter value (no tag column needed):
#   boundary        = true_p10 == 0.01
#   coverage sweep  = homogeneous cells at p10 = 0.05 across verified_coverage
#   confusion sweep = conf_effect > 0 across verified_coverage (0.10 to 0.90)
#   core 3-regime   = p10 in {0.05, 0.20} & verified_coverage in {0.10, 0.30}

# --- run: parallel across fits. workers = physical cores - 2, one chain each
#     (keep workers x parallel_chains <= cores). The confusion arm gets more
#     replicates than the rest; split the design by conf_effect > 0 and run the
#     two halves at different `reps`, then bind. summarise_pilot() groups by the
#     parameter values (p10, coverage, conf_effect, ...) rather than the rep/cell
#     index, so binding two runs with different reps is safe: each cell's
#     coverage is averaged over ALL of its replicates regardless of source.
#     MC SE on a coverage near 0.05 or 0.95: 100 reps ~ 0.022; 300 reps ~ 0.013.
reps_main      <- 100
reps_confusion <- 300   # <- set to 200 for a ~10 h run instead of ~13 h ideal

is_conf     <- design$conf_effect > 0
design_main <- design[!is_conf, , drop = FALSE]   # 13 cells: baseline, Beta, boundary, coverage sweep
design_conf <- design[ is_conf, , drop = FALSE]   # 10 cells: confusion x verification (0.10 to 0.90)

fit_args <- list(iter_warmup = 1000, iter_sampling = 1000,
                 adapt_delta = 0.95, parallel_chains = 1)

# Distinct base_seed per run so the two halves draw from disjoint seed ranges.
res_main <- run_pilot(design_main, reps = reps_main, stan_file = stan_file,
                      base_seed = 1000, parallel = TRUE, workers = 16, fit_args = fit_args)
res_conf <- run_pilot(design_conf, reps = reps_confusion, stan_file = stan_file,
                      base_seed = 5000, parallel = TRUE, workers = 16, fit_args = fit_args)

res <- dplyr::bind_rows(res_main, res_conf)

saveRDS(res,                    file.path("data", "fp_sim_results.rds"))

saveRDS(summarise_pilot(res),   file.path("data", "fp_sim_summary.rds"))

print(summarise_pilot(res), width = Inf)
