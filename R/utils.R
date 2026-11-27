# =============================================================================
# R/utils.R
# Shared configuration and helper functions for the forest-exposure pipeline.
#
# Every script in scripts/ starts with `source(here::here("R", "utils.R"))`.
# No script depends on objects left in the global environment by another
# script (this replaces the submitted workflow, in which 09_correlationVectors.R
# required objects `edge`, `patch`, `isol`, `fire` created interactively by
# scripts 01-04). Intermediate results are written to data/derived/ instead.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})

options(scipen = 999, dplyr.summarise.inform = FALSE)

# ---- Paths ------------------------------------------------------------------
path_raw     <- function(...) here::here("data", "raw", ...)
# derived data and outputs are kept separate per collection
path_derived <- function(...) { d <- here::here("data", "derived", Sys.getenv("DEG_COLLECTION", "col9")); dir.create(d, FALSE, TRUE); file.path(d, ...) }
path_fig     <- function(...) { d <- here::here("outputs", Sys.getenv("DEG_COLLECTION", "col9"), "figures"); dir.create(d, FALSE, TRUE); file.path(d, ...) }
path_tab     <- function(...) { d <- here::here("outputs", Sys.getenv("DEG_COLLECTION", "col9"), "tables"); dir.create(d, FALSE, TRUE); file.path(d, ...) }

# ---- Study configuration ------------------------------------------------------
# Which data collection to run. Set before sourcing, e.g.
#   Sys.setenv(DEG_COLLECTION = "col11"); source("run_all.R")
# or from a terminal: DEG_COLLECTION=col11 Rscript run_all.R
#   col9  : tables used in the submitted manuscript (LULC Col. 9), 1986-2022
#   col11 : MapBiomas Degradation Module tables "11.1a", analysed 1986-2024
COLLECTION <- Sys.getenv("DEG_COLLECTION", "col9")
stopifnot(COLLECTION %in% c("col9", "col11"))

CFG_BY_COLLECTION <- list(
  col9 = list(
    year_start = 1986, year_end = 2022,
    edge_thresholds  = c(30, 60, 90, 120, 150, 300, 600, 1000),
    patch_thresholds = c(3, 5, 10, 25, 50, 75),
    fire_theme = "recurrence"),
  col11 = list(
    # 1986-2024 (39 annual maps; 2025 is in the tables but left out by the authors'
    # decision, 27 Nov 2026 - consistent with LULC Col. 10.1/Fire 4.1 period of ATBD v2)
    year_start = 1986, year_end = 2024,
    # edges up to 5 km exist in the tables; the paper keeps 30-1000 m (R2 5.2)
    edge_thresholds  = c(30, 60, 90, 120, 150, 300, 600, 1000),
    # small patches harmonized up to 100 ha = target size of the isolation metric (R2 5.4)
    patch_thresholds = c(5, 10, 25, 50, 100),
    fire_theme = "fireFrequency")
)

CFG <- c(CFG_BY_COLLECTION[[COLLECTION]], list(
  collection = COLLECTION,
  # MapBiomas level_2 labels treated as forest (GEE remap 3, 5, 6, 49).
  # NOTE: "Magrove" is the spelling used in the exported tables; keep it.
  forest_classes = c("Forest Formation", "Magrove", "Flooded Forest", "Wooded Restinga"),
  # Literature-based scenario used for PCA, correlations and the forest-type ranking
  scenario = list(edge = 150, patch = 50, isolation = 5, fire = 1),
  # Isolation parameters of the main analysis (source >= 1000 ha, target <= 100 ha).
  # Other combinations are used in sensitivity tests.
  isolation_source_ha = 1000,
  isolation_target_ha = 100,
  biome_order = c("Amazon", "Caatinga", "Cerrado", "Atlantic Forest", "Pampa", "Pantanal"),
  driver_order = c("Edge area", "Small-sized patches", "Habitat isolation", "Fire frequency")
))

biome_en <- c("Amazônia" = "Amazon", "Caatinga" = "Caatinga", "Cerrado" = "Cerrado",
              "Mata Atlântica" = "Atlantic Forest", "Pampa" = "Pampa", "Pantanal" = "Pantanal")

# ---- Reading GEE exports -----------------------------------------------------
# Biome-level tables exported from the MapBiomas statistics workflow:
# semicolon separated, decimal comma, latin1, one column per year.
read_mb_table <- function(file) {
  readr::read_delim(file, delim = ";",
                    locale = readr::locale(decimal_mark = ",", encoding = "latin1"),
                    col_types = readr::cols(.default = "c"), show_col_types = FALSE) |>
    tidyr::pivot_longer(matches("^[0-9]{4}$"), names_to = "year", values_to = "area_ha") |>
    mutate(year = as.integer(year),
           area_ha = readr::parse_number(area_ha, locale = readr::locale(decimal_mark = ",")),
           biome = unname(biome_en[NAME])) |>
    filter(level_2 %in% CFG$forest_classes,
           year >= CFG$year_start, year <= CFG$year_end)
}

# Collection 11 tables are distributed by MapBiomas as .xlsx with the same layout
read_mb_xlsx <- function(file) {
  readxl::read_xlsx(file) |>
    mutate(across(-matches("^[0-9]{4}$"), as.character)) |>
    tidyr::pivot_longer(matches("^[0-9]{4}$"), names_to = "year", values_to = "area_ha") |>
    mutate(year = as.integer(year), area_ha = as.numeric(area_ha),
           biome = unname(biome_en[NAME])) |>
    filter(level_2 %in% CFG$forest_classes,
           year >= CFG$year_start, year <= CFG$year_end)
}

# Sum forest classes, split "value" (exposed) and "reference" (all forest) rows,
# and join them by explicit keys (the submitted scripts attached absolute values
# by row position, which is fragile).
exposure_from_long <- function(df, threshold_col, driver_label) {
  df <- df |> mutate(threshold = as.numeric(.data[[threshold_col]]))
  exposed <- df |> filter(key == "value") |>
    group_by(biome, threshold, year) |> summarise(area_exposed_ha = sum(area_ha, na.rm = TRUE))
  forest  <- df |> filter(key == "reference") |>
    group_by(biome, threshold, year) |> summarise(area_forest_ha = sum(area_ha, na.rm = TRUE))
  inner_join(exposed, forest, by = c("biome", "threshold", "year")) |>
    mutate(driver = driver_label)
}

# Fire: the table holds, for each year, forest area by number of times burned
# (theme "recurrence" in Col. 9 / "fireFrequency" in Col. 11, column `value` =
# number of fires since 1985).
# Exposure at threshold k = forest area burned >= k times.
exposure_fire <- function(df, k_max = 10) {
  df <- df |> filter(theme == CFG$fire_theme) |> mutate(n_fires = as.integer(value))
  forest <- df |> filter(key == "reference") |>
    group_by(biome, year) |> summarise(area_forest_ha = sum(area_ha, na.rm = TRUE))
  burned <- df |> filter(key == "value", n_fires >= 1) |>
    group_by(biome, year, n_fires) |> summarise(a = sum(area_ha, na.rm = TRUE))
  tidyr::expand_grid(distinct(forest, biome, year), threshold = seq_len(k_max)) |>
    left_join(burned, by = c("biome", "year"), relationship = "many-to-many") |>
    group_by(biome, year, threshold) |>
    summarise(area_exposed_ha = sum(a[n_fires >= threshold], na.rm = TRUE)) |>
    left_join(forest, by = c("biome", "year")) |>
    mutate(driver = "Fire frequency")
}

# Isolation for Collection 11 is produced by the Colab pipeline
# gee/col11/isolation_pipeline/ (stage S5), one CSV per year, WIDE format:
#   year, territory, ref_ha, uso_t<T>_s<S>_d<D>, ...
# territory = biome_code * 100 + LULC class (30 m); ref_ha = forest area;
# uso_* = forest area in target patches <= T px whose nearest source patch
# (>= S px) is > D km away. Classes are CUMULATIVE in D (> 5 includes > 10, > 20).
# TODO: confirm the biome codes of 'biomas-raster-41' (Pantanal = 3 in the module scripts);
# run iso.check_inputs(cfg) in the notebook to list the codes present.
biome_code <- c(`1` = "Amazon", `2` = "Caatinga", `3` = "Pantanal",
                `4` = "Cerrado", `5` = "Atlantic Forest", `6` = "Pampa")
read_isolation_col11 <- function(dir) {
  files <- list.files(dir, pattern = "\\.csv$", full.names = TRUE)
  if (length(files) == 0) return(tibble())
  x <- purrr::map_dfr(files, readr::read_csv, show_col_types = FALSE) |>
    mutate(biome = unname(biome_code[as.character(territory %/% 100)]),
           lulc_class = territory %% 100) |>
    filter(lulc_class %in% c(3, 5, 6, 49), year >= CFG$year_start, year <= CFG$year_end)
  if (anyNA(x$biome)) stop("Unknown biome code in isolation tables: check `biome_code` in R/utils.R")
  if ("dist_class" %in% names(x)) return(isolation_from_js_long(x))
  ref <- x |> group_by(biome, year) |> summarise(area_forest_ha = sum(ref_ha))
  x |> select(biome, year, starts_with("uso_")) |>
    tidyr::pivot_longer(starts_with("uso_"), names_to = "combo", values_to = "a") |>
    tidyr::extract(combo, c("target_ha", "source_ha", "threshold"),
                   "uso_t(\\d+)_s(\\d+)_d(\\d+)", convert = TRUE) |>
    group_by(biome, year, source_ha, target_ha, threshold) |>
    summarise(area_exposed_ha = sum(a, na.rm = TRUE)) |>
    ungroup() |>
    mutate(threshold = threshold / 1000) |>   # band suffix d<D> is in metres
    left_join(ref, by = c("biome", "year")) |>
    mutate(driver = "Habitat isolation")
}

# LONG format of gee/col11/isolation_forest_col11.js (Code Editor):
#   year, territory, source_ha, target_ha, dist_class, area_ha
#   dist_class = LOWER threshold (m) of an EXCLUSIVE distance class
#   (e.g. 100, 200, 500, 1000, 5000, 10000); dist_class 0 = reference forest area.
# Converted to CUMULATIVE exposure: threshold d (km) = forest at >= d from the
# nearest source, i.e. the sum of all classes with lower bound >= d. Any number of
# thresholds is supported; threshold is returned in km (0.5, 1, 2, 5, 10).
isolation_from_js_long <- function(x) {
  ref <- x |> filter(dist_class == 0) |>
    group_by(biome, year) |> summarise(area_forest_ha = sum(area_ha), .groups = "drop")
  cls <- x |> filter(dist_class > 0) |>
    group_by(biome, year, source_ha, target_ha, dist_class) |>
    summarise(a = sum(area_ha), .groups = "drop")
  thr <- sort(unique(cls$dist_class))
  tidyr::crossing(cls |> distinct(biome, year, source_ha, target_ha), threshold_m = thr) |>
    left_join(cls, by = c("biome", "year", "source_ha", "target_ha"),
              relationship = "many-to-many") |>
    group_by(biome, year, source_ha, target_ha, threshold_m) |>
    summarise(area_exposed_ha = sum(a[dist_class >= threshold_m], na.rm = TRUE), .groups = "drop") |>
    mutate(threshold = threshold_m / 1000) |> select(-threshold_m) |>
    left_join(ref, by = c("biome", "year")) |>
    mutate(driver = "Habitat isolation")
}

# Brazil = sum of biomes. Kept only for descriptive figures/tables; it is NOT
# used as an extra observation in PCA or correlations (R2 comment 6.1).
add_brazil <- function(x) {
  br <- x |> group_by(driver, threshold, year) |>
    summarise(area_exposed_ha = sum(area_exposed_ha), area_forest_ha = sum(area_forest_ha)) |>
    mutate(biome = "Brazil")
  bind_rows(x, br) |>
    mutate(pct_exposed = 100 * area_exposed_ha / area_forest_ha,
           biome = factor(biome, levels = c("Brazil", CFG$biome_order)),
           driver = factor(driver, levels = CFG$driver_order))
}

# ---- Statistics ----------------------------------------------------------------
# Mann-Kendall test implemented through Kendall's tau between time and value
# (base R; identical statistic, tie-corrected normal approximation), and Sen's
# slope as the median of all pairwise slopes. Avoids an extra dependency.
mk_sen <- function(year, y) {
  ok <- is.finite(y); year <- year[ok]; y <- y[ok]
  if (length(unique(y)) < 3) return(tibble(tau = NA_real_, p_value = NA_real_, sen_slope = NA_real_, n = length(y)))
  ct <- suppressWarnings(cor.test(year, y, method = "kendall", exact = FALSE))
  ij <- utils::combn(length(y), 2)
  slopes <- (y[ij[2, ]] - y[ij[1, ]]) / (year[ij[2, ]] - year[ij[1, ]])
  tibble(tau = unname(ct$estimate), p_value = ct$p.value,
         sen_slope = stats::median(slopes), n = length(y))
}

# ---- Figures -----------------------------------------------------------------
# Sequential palette (ColorBrewer RdPu) for ordered thresholds (R1 comment on Fig. 1, 2, Box 1).
# lightest 3 RdPu tones dropped so that every line stays visible on white
seq_pal <- function(n) grDevices::colorRampPalette(RColorBrewer_RdPu[4:9])(n)
RColorBrewer_RdPu <- c("#fff7f3", "#fde0dd", "#fcc5c0", "#fa9fb5", "#f768a1",
                       "#dd3497", "#ae017e", "#7a0177", "#49006a")

theme_paper <- function(base = 10) {
  theme_bw(base_size = base) +
    theme(panel.grid.minor = element_blank(),
          strip.background = element_rect(fill = "grey95", colour = NA),
          legend.position = "bottom")
}

save_fig <- function(plot, name, width, height, dpi = 600) {
  ggsave(path_fig(paste0(name, ".png")), plot, width = width, height = height, dpi = dpi)
  ggsave(path_fig(paste0(name, ".pdf")), plot, width = width, height = height, device = grDevices::cairo_pdf)
  invisible(plot)
}

write_tab <- function(x, name) {
  readr::write_csv(x, path_tab(paste0(name, ".csv")))
  invisible(x)
}
