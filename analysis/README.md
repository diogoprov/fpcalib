# analysis/

Scripts that reproduce the study. Run each from the compendium root, in
numerical order. Steps 01, 03, 04, and 05 fit Stan models and take hours on a
multi-core machine; their scored outputs are already in `data/`, so 02 and 06
run in seconds without them.

1. `01_run_simulation.R`: main study, 23 cells (homogeneous, unstructured, and
   structured false positives; near-boundary cells; verification sweeps), 100
   replicates per cell and 300 for the structured-confusion cells. Fits the
   constant-p10 Stan model and `occuFP`. Writes `data/fp_sim_results.rds` and
   `data/fp_sim_summary.rds`.
2. `02_make_figures.R`: coverage figures of the main study, written to
   `analysis/figures/` (not tracked by git).
3. `03_run_fix_arm.R`: the false-positive rate modelled on the occupancy
   covariate, in Stan and in `occuFP`. Writes `data/fp_fix_*.rds`.
   `00_smoke_test_fix.R` is a quick check of this arm.
4. `04_positive_control.R`: the false-positive rate modelled on the confusing
   gradient w and on a noisy proxy of it, refitted to the datasets of 01 and
   paired with those fits; stops if the regenerated datasets do not match.
   Writes `data/fp_positive_control_*.rds` and the diagnostic figure
   `manuscript/figures/figE_positive_control_b1.pdf`.
5. `05_confusion_intensity.R`: strength × correlation of the confusion under the
   constant-p10 model. Writes `data/fp_intensity_*.rds` and the diagnostic
   figure `manuscript/figures/figF_confusion_intensity.pdf`.
6. `06_manuscript_figures.R`: Figures 6 and 7 of the manuscript from the
   summaries of 01, 03, 04, and 05.

`diagnose_divergences.R` inspects the fits with divergent transitions.
