# =============================================================================
# 03_trends_rates.R  ->  Table S3 (new), Table S4 (new)
# Trend significance and rates of change for every biome x driver x threshold.
#
# Addresses:
#   R2 6.3  Mann-Kendall test + Sen's slope for each biome, driver and threshold;
#           Benjamini-Hochberg adjustment across all tests.
#   R2 6.4  Absolute (ha/yr) and relative (percentage points/yr; % change of the
#           1986 value) rates, to support/correct "the Cerrado experienced the
#           fastest increase".
#   R2 8.2  Separates change in area (ha) from change in proportion (p.p.).
#   R2 3.4  Fire frequency is cumulative (fires since 1985); its trend is
#           reported but flagged as cumulative, not as an independent temporal trend.
# =============================================================================
source(here::here("R", "utils.R"))

exposure <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE)

trends <- exposure |>
  group_by(driver, biome, threshold) |>
  group_modify(~ {
    pct <- mk_sen(.x$year, .x$pct_exposed)
    abs <- mk_sen(.x$year, .x$area_exposed_ha)
    y0 <- .x |> filter(year == CFG$year_start); y1 <- .x |> filter(year == CFG$year_end)
    tibble(
      tau = pct$tau, p_value = pct$p_value,
      sen_pp_per_yr = pct$sen_slope,
      sen_ha_per_yr = abs$sen_slope,
      pct_start = y0$pct_exposed, pct_end = y1$pct_exposed,
      delta_pp = y1$pct_exposed - y0$pct_exposed,
      rel_change_pct = ifelse(y0$pct_exposed > 0,
                              100 * (y1$pct_exposed - y0$pct_exposed) / y0$pct_exposed, NA_real_),
      area_start_ha = y0$area_exposed_ha, area_end_ha = y1$area_exposed_ha,
      delta_area_ha = y1$area_exposed_ha - y0$area_exposed_ha)
  }) |>
  ungroup() |>
  mutate(p_adj_BH = p.adjust(p_value, method = "BH"),
         trend = case_when(is.na(p_adj_BH) ~ "insufficient data",
                           p_adj_BH < 0.05 & tau > 0 ~ "increase",
                           p_adj_BH < 0.05 & tau < 0 ~ "decrease",
                           TRUE ~ "no significant trend"),
         note = ifelse(driver == "Fire frequency",
                       "cumulative metric (fires since 1985): monotonic by construction", ""))
write_tab(trends, "tableS3_trends_mannkendall_sen")

# Summary for the text: how many biome x driver x threshold combinations increase?
summary_counts <- trends |> filter(biome != "Brazil") |>
  count(driver, trend) |> pivot_wider(names_from = trend, values_from = n, values_fill = 0)
write_tab(summary_counts, "tableS3b_trend_counts")

# Rates under the literature-based scenario (one threshold per driver) - Table S4
sc <- CFG$scenario
scen <- trends |>
  filter((driver == "Edge area" & threshold == sc$edge) |
         (driver == "Small-sized patches" & threshold == sc$patch) |
         (driver == "Habitat isolation" & threshold == sc$isolation) |
         (driver == "Fire frequency" & threshold == sc$fire)) |>
  group_by(driver) |>
  mutate(rank_pp_per_yr = rank(-sen_pp_per_yr[biome != "Brazil"])[match(biome, biome[biome != "Brazil"])],
         rank_ha_per_yr = rank(-sen_ha_per_yr[biome != "Brazil"])[match(biome, biome[biome != "Brazil"])]) |>
  ungroup()
write_tab(scen, "tableS4_rates_scenario")
print(scen |> select(driver, biome, sen_pp_per_yr, sen_ha_per_yr, rank_pp_per_yr, rank_ha_per_yr, trend), n = 40)
message("03_trends_rates: done.")
