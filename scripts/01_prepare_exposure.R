# =============================================================================
# 01_prepare_exposure.R
# Build one tidy table with forest area exposed to each driver, by biome,
# threshold and year (1986-2022), from the GEE exports in data/raw/biome/.
#
# Output: data/derived/<collection>/exposure_biome.csv  (collection: see R/utils.R)
#   biome | driver | threshold | year | area_exposed_ha | area_forest_ha | pct_exposed
#
# Threshold semantics (all CUMULATIVE classes in the biome tables):
#   Edge area ............ forest within <= threshold m of anthropogenic land use
#   Small-sized patches .. forest in native-vegetation patches <= threshold ha
#   Habitat isolation .... forest in target patches (<= 100 ha) located >= threshold km
#                          from source patches (>= 1000 ha)   [other combos: sensitivity]
#   Fire frequency ....... forest burned >= threshold times since 1985
#
# Replaces: 01_graphicsEdge_Forest.R, 02_graphicsPatch_Forest.R,
#           03_graphicsIsolation_Forest.R, 04_graphics_fireFrequency_Forest.R
#           (data-preparation part) and the table_fig1_v2/ intermediate CSVs.
# =============================================================================
source(here::here("R", "utils.R"))

if (CFG$collection == "col9") {
  f <- function(x) path_raw("biome", paste0("brazil-refined-biome-", x, "-9.0.1a.csv"))
  edge  <- read_mb_table(f("edges")) |> exposure_from_long("edge_size", "Edge area")
  patch <- read_mb_table(f("patch")) |> exposure_from_long("patch_size", "Small-sized patches")
  fire  <- read_mb_table(f("fire"))  |> exposure_fire(k_max = 10)

  iso_all <- read_mb_table(f("isolation")) |>
    mutate(distance = as.numeric(distance)) |>
    group_by(medium_size, big_size) |>
    group_modify(~ exposure_from_long(.x, "distance", "Habitat isolation")) |>
    ungroup() |>
    mutate(target_ha = as.numeric(medium_size), source_ha = as.numeric(big_size)) |>
    select(-medium_size, -big_size)
} else {
  # Collection 11 (Degradation Module tables "11.1a", xlsx).
  # Edge table has an extra edge_age dimension (value rows: age >= 1 years;
  # reference rows: age 0); summing over ages gives the edge area per distance.
  f <- function(x) path_raw("col11", paste0("brazil-refined-biome-", x, "-11.1a.xlsx"))
  edge  <- read_mb_xlsx(f("edges")) |> exposure_from_long("edge_size", "Edge area")
  patch <- read_mb_xlsx(f("patch")) |> exposure_from_long("patch_size", "Small-sized patches")
  fire  <- read_mb_xlsx(f("fire"))  |> exposure_fire(k_max = 10)
  # Isolation is not part of the 11.1a tables: produced by
  # the Colab pipeline gee/col11/isolation_pipeline/ and read here once the CSVs exist.
  iso_all <- read_isolation_col11(path_raw("col11", "isolation"))
}
edge  <- edge  |> filter(threshold %in% CFG$edge_thresholds)
patch <- patch |> filter(threshold %in% CFG$patch_thresholds)

isolation <- if (nrow(iso_all) == 0) tibble() else iso_all |>
  filter(target_ha == CFG$isolation_target_ha, source_ha == CFG$isolation_source_ha) |>
  select(-target_ha, -source_ha)

exposure <- bind_rows(edge, patch, isolation, fire) |> add_brazil() |>
  arrange(driver, biome, threshold, year)
write_csv(exposure, path_derived("exposure_biome.csv"))

# Isolation: all source/target combinations, for sensitivity analyses (R2 3.3, 5.4, 9.4)
if (nrow(iso_all) > 0) {
  iso_sens <- iso_all |> group_by(target_ha, source_ha) |>
    group_modify(~ add_brazil(.x)) |> ungroup()
  write_csv(iso_sens, path_derived("exposure_isolation_all_params.csv"))
} else {
  message("Habitat isolation not available for ", CFG$collection, " - run gee/col11/isolation_pipeline/run_isolation_col11_colab.ipynb")
  unlink(path_derived("exposure_isolation_all_params.csv"))
}

# Sanity checks: proportions within [0, 100] and monotonic across cumulative thresholds
stopifnot(all(exposure$pct_exposed >= 0 & exposure$pct_exposed <= 100, na.rm = TRUE))
mono <- exposure |> group_by(driver, biome, year) |> arrange(threshold, .by_group = TRUE) |>
  summarise(ok = if (first(driver) %in% c("Edge area", "Small-sized patches"))
                    all(diff(pct_exposed) >= -1e-9) else all(diff(pct_exposed) <= 1e-9))
if (!all(mono$ok)) warning("Non-monotonic cumulative thresholds in: ",
                           paste(unique(paste(mono$driver[!mono$ok], mono$biome[!mono$ok])), collapse = "; "))
message("01_prepare_exposure: ", nrow(exposure), " rows written.")
