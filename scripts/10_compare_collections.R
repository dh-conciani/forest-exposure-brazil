# =============================================================================
# 10_compare_collections.R  ->  Table S10 (new): Collection 9 vs Collection 11
#
# Same driver, biome, threshold and year in both collections (overlap 1986-2022).
# Documents how much the update of the MapBiomas data changes the results the
# reviewers saw, and supports the statement in the response letter.
# Needs data/derived/col9/ and data/derived/col11/ (run run_all.R for both).
# =============================================================================
source(here::here("R", "utils.R"))
f9  <- here::here("data", "derived", "col9",  "exposure_biome.csv")
f11 <- here::here("data", "derived", "col11", "exposure_biome.csv")
if (!all(file.exists(c(f9, f11)))) {
  message("10: run run_all.R with DEG_COLLECTION=col9 and =col11 first.")
} else {
  a <- read_csv(f9,  show_col_types = FALSE) |> select(driver, biome, threshold, year, pct_col9  = pct_exposed, forest_col9  = area_forest_ha)
  b <- read_csv(f11, show_col_types = FALSE) |> select(driver, biome, threshold, year, pct_col11 = pct_exposed, forest_col11 = area_forest_ha)
  cmp <- inner_join(a, b, by = c("driver", "biome", "threshold", "year")) |>
    mutate(diff_pp = pct_col11 - pct_col9, forest_diff_pct = 100 * (forest_col11 / forest_col9 - 1))
  sc <- CFG$scenario
  out <- cmp |>
    filter(year %in% c(1986, 2022),
           (driver == "Edge area" & threshold == sc$edge) | (driver == "Small-sized patches" & threshold == sc$patch) |
           (driver == "Habitat isolation" & threshold == sc$isolation) | (driver == "Fire frequency" & threshold == sc$fire)) |>
    arrange(driver, biome, year)
  d <- here::here("outputs", "comparison"); dir.create(d, FALSE, TRUE)
  readr::write_csv(cmp, file.path(d, "col9_vs_col11_all.csv"))
  readr::write_csv(out, file.path(d, "tableS10_col9_vs_col11_scenario.csv"))
  print(out |> select(driver, biome, year, pct_col9, pct_col11, diff_pp, forest_diff_pct), n = 60)
}
