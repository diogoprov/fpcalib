# analysis/

Scripts that reproduce the study, in order. Run each with the compendium root
as the working directory.

1. `01_run_simulation.R` — simulates 100 replicates per cell across the three
   false-positive regimes, fits the Stan model and `occuFP` to each dataset, and
   saves the scored per-replicate results to `data/fp_sim_100reps_results.rds`
   and the per-cell summary to `data/fp_sim_100reps_summary.rds`. This is the
   expensive step (a few hours on 18 cores). Lower `reps` for a quick check.

2. `02_make_figures.R` — reads the saved results and writes the coverage figures
   to `analysis/figures/`. Fast; needs no rerun of step 1.

The `figures/` directory is created on demand and is not tracked by git.
