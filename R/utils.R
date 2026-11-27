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
path_derived <- function(...) here::here("data", "derived", ...)
path_fig     <- function(...) here::here("outputs", "figures", ...)
path_tab     <- function(...) here::here("outputs", "tables", ...)

# ---- Study configuration ------------------------------------------------------
# Period analysed in the manuscript. 1986-2022 = 37 annual maps (R2 comment 1.7).
CFG <- list(
  year_start = 1986,
  year_end   = 2022,
  # MapBiomas Collection 9 level_2 labels treated as forest (GEE remap 3, 5, 6, 49).
  # NOTE: "Magrove" is the spelling used in the exported tables; keep it.
  forest_classes = c("Forest Formation", "Magrove", "Flooded Forest", "Wooded Restinga"),
  # Literature-based scenario used for PCA, correlations and the forest-type ranking
  scenario = list(edge = 150, patch = 50, isolation = 5, fire = 1),
  # Isolation parameters fixed in the submitted analysis (source >= 1000 ha,
  # target patches <= 100 ha). Other combinations are used in sensitivity tests.
  isolation_source_ha = 1000,
  isolation_target_ha = 100,
  biome_order = c("Amazon", "Caatinga", "Cerrado", "Atlantic Forest", "Pampa", "Pantanal"),
  driver_order = c("Edge area", "Small-sized patches", "Habitat isolation", "Fire frequency")
)

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
# (theme == "recurrence", column `value` = number of fires since 1985).
# Exposure at threshold k = forest area burned >= k times.
exposure_fire <- function(df, k_max = 10) {
  df <- df |> filter(theme == "recurrence") |> mutate(n_fires = as.integer(value))
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
