# =============================================================================
# figs_didaticas_curiango.R
# Duas figuras para EXPLICAR a simulacao (nao para reportar numeros finais):
#   (1) coverage como "varetas vs linha da verdade" (caterpillar)
#   (2) a logica entra/sai da simulacao (fluxo grViz)
# =============================================================================
library(tidyverse)

# rotula o cenario a partir das colunas de "arm" (mesma logica do plot_pilot).
# NB: true_beta_conc vem 0 (nao NA) nos bracos base/confusao, entao o teste e
# ` > 0`, nao `!is.na(...)` (que marcaria tudo como Beta).
add_scenario <- function(res) {
  res |>
    mutate(scenario = case_when(
      true_conf_effect > 0 ~ "confusao (estruturada)",
      true_beta_conc  > 0  ~ "Beta (nao estruturada)",
      true_sigma_p10  > 0  ~ "logit-normal (nao estr.)",
      TRUE                 ~ "base"))
}

# Fig 1 -- caterpillar de coverage, a partir do `res` REAL do run_pilot().
# Colunas: stan_<param>_est/_lo/_hi (do fit_both) e o valor verdadeiro
# (true_b1 para b1; true_p10_marginal para p10, que é o alvo sob heterogeneidade).
plot_coverage_caterpillar <- function(res, param = c("b1", "p10"),
                                      scenarios = c("base", "confusao (estruturada)")) {
  param <- match.arg(param)
  est <- paste0("stan_", param, "_est")
  lo  <- paste0("stan_", param, "_lo")
  hi  <- paste0("stan_", param, "_hi")
  truth_col <- if (param == "p10") "true_p10_marginal" else paste0("true_", param)

  d <- add_scenario(res) |>
    filter(stan_ok, scenario %in% scenarios) |>
    rename(est = all_of(est), lo = all_of(lo), hi = all_of(hi),
           truth = all_of(truth_col)) |>
    filter(!is.na(lo), !is.na(hi)) |>
    group_by(scenario) |> arrange(est, .by_group = TRUE) |>
    mutate(rank = row_number(), caught = lo <= truth & hi >= truth) |> ungroup()

  labs_df <- d |> group_by(scenario) |>
    summarise(cov = mean(caught), n = n(), .groups = "drop") |>
    mutate(txt = sprintf("cobertura = %d/%d = %.0f%%", round(cov * n), n, 100 * cov))

  ggplot(d, aes(y = rank)) +
    geom_vline(aes(xintercept = truth), linetype = "dashed", linewidth = .6,
               colour = "grey20") +
    geom_linerange(aes(xmin = lo, xmax = hi, colour = caught), linewidth = .7) +
    geom_point(aes(x = est, colour = caught), size = 1) +
    geom_text(data = labs_df, aes(x = -Inf, y = Inf, label = txt),
              hjust = -0.05, vjust = 1.5, size = 4, fontface = "bold",
              colour = "grey20", inherit.aes = FALSE) +
    facet_wrap(~scenario) +
    scale_colour_manual(values = c(`TRUE` = "#4C72B0", `FALSE` = "#D55E00"),
                        labels = c(`TRUE` = "IC de 95% cruza a verdade",
                                   `FALSE` = "IC de 95% erra a verdade"),
                        name = NULL) +
    labs(x = paste0("estimativa (", param, ")"),
         y = "replicas da simulacao (ordenadas)",
         title = "Coverage = fracao de intervalos que cruzam a linha da verdade") +
    theme_bw(base_size = 12) +
    theme(axis.text.y = element_blank(), axis.ticks.y = element_blank(),
          legend.position = "bottom")
}
# uso: plot_coverage_caterpillar(res, "b1")
#      ggsave("fig_coverage.pdf", width = 10, height = 6)

# -----------------------------------------------------------------------------
# Fig 2 -- fluxo da logica da simulacao (DiagrammeR/grViz).
# O .dot completo esta em fig_logica_simulacao.dot; aqui so o wrapper para
# renderizar e exportar em R.
# -----------------------------------------------------------------------------
render_fluxo <- function(dot_path = "fig_logica_simulacao.dot") {
  library(DiagrammeR)
  g <- grViz(paste(readLines(dot_path, encoding = "UTF-8"), collapse = "\n"))
  # exportar (precisa de DiagrammeRsvg + rsvg):
  # library(DiagrammeRsvg); library(rsvg)
  # g |> export_svg() |> charToRaw() |> rsvg_pdf("fig_logica_simulacao.pdf")
  g
}
