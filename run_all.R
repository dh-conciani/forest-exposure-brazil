# =============================================================================
# run_all.R - reproduces every table and figure of the revised manuscript that
# is derived from the GEE exports in data/raw/.
#   Rscript run_all.R
# Requires: R >= 4.3 and the packages pinned in renv.lock (renv::restore()).
# =============================================================================
if (file.exists("renv/activate.R")) source("renv/activate.R")
scripts <- c(
  "01_prepare_exposure.R",          # tidy exposure table (biome x driver x threshold x year)
  "02_fig1_timeseries.R",           # Figure 1
  "03_trends_rates.R",              # Tables S3, S4  (Mann-Kendall, Sen, rates)
  "04_pca_correlations.R",          # Figure 3, Table S5, Figure S2
  "05_threshold_sensitivity.R",     # Figure S3, Table S6
  "06_denominator_decomposition.R", # Table S7
  "07_forest_type_ranking.R",       # Figure 4 / Box 1, Table S8
  "08_text_consistency_checks.R"    # numbers quoted in the text vs. recomputed
)
for (s in scripts) {
  message("\n==== ", s, " ====")
  t0 <- Sys.time()
  sys.source(here::here("scripts", s), envir = new.env())  # clean environment per script
  message("     finished in ", round(difftime(Sys.time(), t0, units = "secs"), 1), " s")
}
writeLines(capture.output(sessionInfo()), here::here("outputs", "sessionInfo.txt"))
