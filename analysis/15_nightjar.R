# =============================================================================
# 15_nightjar.R
# The nightjar example of the manuscript (Figure 7): the false-positive model
# fitted to the curiango data of crywolf at four classifier thresholds, with
# fp ~ 1 at 0.2, 0.4, 0.6 and 0.8 and fp ~ temp + rh at 0.2 and 0.4. Occupancy
# ~ temp + rh + moon, detection ~ bio + aci, recorder random intercept, 4 chains
# of 1000 + 1000 iterations, seed 1. About 9 min per fit on 16 cores.
#
# Uses crywolf 1.9.0, the version cited in the manuscript, from a private
# library so that the version installed for 07-12 is untouched:
#   R CMD INSTALL -l .lib-crywolf-1.9.0 <crywolf source at tag v1.9.0>
#   RENV_ACTIVATE_PROJECT=FALSE Rscript analysis/15_nightjar.R [output.rds]
# The default output is data/nightjar_fits.rds. Given another file name, the
# script also reports the largest difference in posterior means from the
# stored data/nightjar_fits.rds (a reproduction check).
# SMOKE=1 runs one short fit only, to test the script.
# Run with the COMPENDIUM ROOT as the working directory.
# =============================================================================
.libPaths(c(".lib-crywolf-1.9.0", .libPaths()))
library(crywolf)
stopifnot(packageVersion("crywolf") == "1.9.0")
source("R/nightjar_data.R")

out_file <- commandArgs(TRUE)[1]
if (is.na(out_file)) out_file <- file.path("data", "nightjar_fits.rds")
smoke <- Sys.getenv("SMOKE") == "1"
nj <- nightjar_data()
runs <- rbind(data.frame(fp = "~ 1", threshold = c(0.2, 0.4, 0.6, 0.8), threads = 4),
              data.frame(fp = "~ temp + rh", threshold = c(0.2, 0.4), threads = 2))
if (smoke) runs <- runs[1, ]

fit_one <- function(fp, th, threads) {
  t0 <- Sys.time()
  auto <- fp_aggregate(nj$occasions, nj$detections, threshold = th, by = "file")
  d <- fp_data(auto, nj$sites, nj$verified, site = "site_night", recorder = "recorder")
  m <- suppressWarnings(fp_occu(d, occ = ~ temp + rh + moon, det = ~ bio + aci,
                                fp = as.formula(fp), random_recorder = TRUE,
                                chains = 4, parallel_chains = 4,
                                threads_per_chain = threads, seed = 1, refresh = 0,
                                show_messages = FALSE,
                                iter_warmup = if (smoke) 50 else 1000,
                                iter_sampling = if (smoke) 50 else 1000))
  list(fp = fp, threshold = th, table = as.data.frame(summary(m)$table),
       diagnostics = m$diagnostics,
       minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
fits <- lapply(seq_len(nrow(runs)), function(k) {
  r <- fit_one(runs$fp[k], runs$threshold[k], runs$threads[k])
  message(sprintf("fp %s, threshold %.1f: %.1f min, min bulk ESS %.0f, min tail ESS %.0f, max R-hat %.4f, divergences %d",
                  r$fp, r$threshold, r$minutes, r$diagnostics$min_ess_bulk,
                  r$diagnostics$min_ess_tail, r$diagnostics$max_rhat,
                  as.integer(r$diagnostics$divergences)))
  r
})
res <- list(fits = fits, crywolf_version = as.character(packageVersion("crywolf")),
            date = Sys.time())

stored <- file.path("data", "nightjar_fits.rds")
if (normalizePath(out_file, mustWork = FALSE) != normalizePath(stored) && file.exists(stored)) {
  old <- readRDS(stored)$fits
  res$check <- do.call(rbind, lapply(fits, function(r) {
    o <- Filter(\(f) f$fp == r$fp && f$threshold == r$threshold, old)[[1]]$table
    n <- r$table[match(o$variable, r$table$variable), ]
    data.frame(fp = r$fp, threshold = r$threshold,
               max_abs_diff_mean = max(abs(n$mean - o$mean), na.rm = TRUE))
  }))
  print(res$check)
}
saveRDS(res, out_file)
