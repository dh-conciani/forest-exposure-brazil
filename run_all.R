# =============================================================================
# run_all.R - reproduces every table and figure of the revised manuscript that
# is derived from the GEE exports in data/raw/.
#   Rscript run_all.R
# Collection: DEG_COLLECTION=col9 (default, submitted data) or col11
#   (MapBiomas Degradation Module 11.1a, 1986-2024):
#   DEG_COLLECTION=col11 Rscript run_all.R
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
  "08_text_consistency_checks.R",   # numbers quoted in the text vs. recomputed (col9)
  "09_edge_age.R",                  # Figure S4, Table S9 (col11)
  "10_compare_collections.R"        # Table S10, col9 vs col11 (needs both runs)
)
for (s in scripts) {
  message("\n==== ", s, " ====")
  t0 <- Sys.time()
  sys.source(here::here("scripts", s), envir = new.env())  # clean environment per script
  message("     finished in ", round(difftime(Sys.time(), t0, units = "secs"), 1), " s")
}
writeLines(capture.output(sessionInfo()), here::here("outputs", paste0("sessionInfo_", Sys.getenv("DEG_COLLECTION", "col9"), ".txt")))
