# AI interaction log — false-positive occupancy simulation (fpcalib)

Traceability record for the human-AI collaboration behind this project, kept to
support the AIdIT disclosure (Drobniak et al. 2026) and the COPE and Wiley
requirements. Maintain it as a running file.

- **Project:** Bayesian false-positive occupancy calibration (fpcalib)
- **AI tool:** Claude (Anthropic), model identifier `claude-opus-4-8`, via the
  Claude / Cowork interface
- **Human authors:** Diogo B. Provete (directing), plus co-authors (Larissa,
  Liliana; Tessa prospective)
- **Where the verbatim record lives:** the full conversation transcript in the
  Claude app is the primary, faithful record. This file is a curated summary,
  not a substitute for it.

## The three layers of traceability (keep all three)

1. **The conversation transcript.** The exact prompts and responses. Export or
   save the session from the Claude app and store a copy with the project. This
   is what a "prompts registry" (AIdIT) actually is.
2. **The git history of the compendium.** If you `git init` and commit fpcalib,
   the commit log is an automatic, timestamped ledger of which files the AI
   touched and when. In this environment commits also carry a `Co-Authored-By:
   Claude` line and a session link, so provenance is built in. Recommend
   committing after each work session.
3. **This curated log.** A human-readable summary of what was AI-assisted, what
   you decided, and how each output was verified. It is what you cite in the
   disclosure and hand to a co-author or editor.

## Session summary — 2026-08 (this collaboration)

*Reconstructed from the session; consult the transcript for the exact wording.*

| Date | Task (AIdIT area) | AI role | Human decision / verification | Output artifact |
|---|---|---|---|---|
| 2026-08 | occuFP CI capture in `fit_both()` (formal analysis) | Wrote the edit | You ran the smoke test, confirmed columns populate | `R/fp_sim_pilot.R` |
| 2026-08 | Divergence diagnosis + reparameterization (validation) | Proposed the `sigma_u` funnel hypothesis and the `estimate_re` toggle | You ran the diagnostic; confirmed 0 divergences, estimates unchanged | `inst/stan/fp_occupancy_re_toggle.stan`, `analysis/diagnose_divergences.R` |
| 2026-08 | Simulation design (methods) | Proposed boundary cell + verification sweep (17 cells) | You approved; run pending | `analysis/01_run_simulation.R` |
| 2026-08 | Figures + model DAG (visualisation) | Generated coverage figures, DAG (DiagrammeR), scheme (Fig 1) | You directed the journal style; reviewed each | `manuscript/figures/*`, `R/fig_dag.R` |
| 2026-08 | Literature verification + positioning (conceptualisation) | Verified model vs Chambert code; positioned vs Stolen 2019, Clare 2021; found the Clare tension | You uploaded the papers and code and pushed for the exact-misspecification check | `claude/verificacao_modelo_vs_chambert.md`, `claude/posicionamento_vs_stolen_clare.md` |
| 2026-08 | Drafting (writing) | Drafted Methods, Results, email, AI disclosure | You set route B and the framing; verified every number and citation | `manuscript/Results_FP_calibration_draft.docx` |

## What to keep, to report later (checklist)

- [ ] Exported transcript of the session(s), stored with the project
- [ ] Model name and identifier, interface, and the dates of use
- [ ] Git history of fpcalib (or a snapshot of `git log`)
- [ ] This log, updated per session
- [ ] For each AI-assisted output: what it was, and how you verified it
- [ ] Note of any place you overrode or corrected the AI (these matter most)

## Template for future entries

| Date | Task (AIdIT area) | AI role | Human decision / verification | Output artifact |
|---|---|---|---|---|
| YYYY-MM-DD |  |  |  |  |
