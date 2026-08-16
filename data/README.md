# data/

Scored simulation outputs, written by `analysis/01_run_simulation.R`. These are
small (~135 KB each) and are kept under version control so the figures reproduce
without rerunning the multi-hour simulation.

- `fp_sim_100reps_results.rds` — one row per (replicate, cell), 1200 rows for
  the 12-cell x 100-replicate design. Columns include the true parameters
  (`true_p10`, `true_p10_marginal`, `true_b1`, `true_psi`, `true_p11`, and the
  heterogeneity settings `true_beta_conc`, `true_conf_effect`, `true_conf_cor`),
  the Stan estimates with 95% credible interval bounds and coverage flags
  (`stan_p10_est/lo/hi/cov`, `stan_b1_est/lo/hi/cov`, `stan_psi_est/cov`), the
  Stan diagnostics (`stan_max_rhat`, `stan_ndiv`, `stan_runtime`), and the
  matching `occuFP` estimates with Wald 95% interval bounds, coverage flags, and
  the degeneracy flag (`occufp_p10_est/lo/hi/cov`, `occufp_psi_est/lo/hi/cov`,
  `occufp_b1_est/lo/hi/cov`, `occufp_degenerate`).

- `fp_sim_100reps_summary.rds` — one row per design cell, produced by
  `summarise_pilot()`: convergence rate, occuFP failure rate, and the coverage
  and bias of both models for `p10` and `b1`.

The interval bounds and coverage flags for `occuFP` are NA on the degenerate
(singular-Hessian) fits, so occuFP coverage and bias are scored only over the
fits that produced a finite interval.
