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
2. `02_make_figures.R`: superseded; coverage figures of the first run of 100
   replicates, kept for the record.
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
6. `06_manuscript_figures.R`: superseded by 14; the earlier drawing of
   Figures 5 and 6 of the manuscript.

7. `07_revision_checks.R`: checks added in the revision of the manuscript,
   refitted with the R package crywolf to the first 100 datasets of 17 cells of
   01, regenerated from their seeds and checked against the original run: the
   cost of the occupancy covariate in the false-positive process when false
   positives are homogeneous, a site random effect on the false-positive rate
   under unstructured heterogeneity, and whether leave-one-site-out
   cross-validation and a posterior predictive check reveal structured
   confusion. Writes `data/fp_revision_results.rds`.
8. `08_observation_confirmation.R`: structured confusion (effect 1.5) under the
   observation-confirmation design, with 5%, 10% or 30% of the automated
   occasions checked, plus two homogeneous cells. Writes
   `data/fp_obsconfirm_results.rds`.
9. `09_revision_summary.R`: summaries, tables and figures of 07, 08 and 10.
   Writes `data/fp_revision_summary.rds`, `analysis/tables/` and
   `analysis/figures/` (the last two not tracked by git).
10. `10_obsconfirm_weak.R`: the design of 08 at the weaker confusion effects
    0.5 and 1.0. Writes `data/fp_obsconfirm_weak_results.rds`.
11. `11_obsconfirm_clare.R`: the design of 08 with false positives that depend
    on the occupancy covariate itself (correlation 1.0), at the confusion
    effects 0.5, 1.0 and 1.5, adding an occupancy model that ignores false
    positives (`unmarked::occu`). Writes `data/fp_obsconfirm_clare_results.rds`.
    It was run on an EC2 spot instance (c7a.48xlarge); the fits are close to,
    but not bitwise equal to, those of the same seeds on macOS.

12. `12_random_fp_long.R`: the site random effect on the false-positive rate
    of 07, refitted with 2,000 + 2,000 iterations to the same 400 datasets of
    the unstructured cells, because it mixed slowly with 1,000 + 1,000. Writes
    `data/fp_revision_rfp_long_results.rds`. Run on EC2 spot instances.

13. `13_fig4_caterpillars.R`: Figure 4 of the manuscript, per-replicate
    intervals of four cells of 01.
14. `14_figs_3_5_6.R`: Figures 3, 5 and 6 of the manuscript from the
    summaries of 01, 03, 04 and 05.
15. `15_nightjar.R`: the nightjar example, six fits of crywolf 1.9.0 to the
    curiango data of that package (about 9 min each on 16 cores). Writes
    `data/nightjar_fits.rds`, the fits reported in the manuscript; given another
    output file, it compares the new fits with the stored ones. Runs with the
    same seed are not bitwise identical, as the likelihood is summed in
    parallel within each chain: `data/nightjar_fits_rerun.rds`, a repeat on
    2026-10-29, differs by up to 0.035 in the posterior means and by up to 0.01
    in the estimates reported in the text. crywolf 1.9.0 is installed in a private library,
    `.lib-crywolf-1.9.0/`, as the header of the script shows.
16. `16_fig7_nightjar.R`: Figure 7 of the manuscript from the fits of 15.

`manuscript/reproduce.qmd` draws Figures 3 to 7 and recomputes every number
reported in the Results and Discussion of the manuscript from `data/`, in
seconds and without Stan; it stops if any number in the text disagrees with
the data (render with `-P strict:false` for a report instead).
`manuscript/appendix-S1.qmd` renders Appendix S1 from the same files.

In 08, 10 and 11 the seed of a task depends on `REPS`, so a test run with
fewer replicates must use another job folder: its files would otherwise be
reused by the full run with the wrong seeds. This happened once in 10 (11
tasks) and was corrected in version 0.2.1.

Scripts 07, 08, 10, 11 and 12 use crywolf 1.9.0.9000 (commit a5d2516 of
https://github.com/diogoprov/crywolf), whose Stan programs and fitting,
simulation and checking functions are those of release 1.9.0. crywolf is not in
`renv.lock`, so run them with `RENV_ACTIVATE_PROJECT=FALSE`, as their headers
show; per-task results are saved in `data/*_jobs/` and an interrupted run
resumes where it stopped.

`diagnose_divergences.R` inspects the fits with divergent transitions.
