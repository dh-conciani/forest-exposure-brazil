# =============================================================================
# 05_threshold_sensitivity.R  ->  Figure S3 (new), Table S6 (new)
#
# Addresses:
#   R2 9.4  How do conclusions and biome rankings change across edge distances
#           (30-1000 m), patch sizes (3-75 ha) and isolation distances (col9 5-20 km; col11 0.5-10 km)?
#   R2 3.3 / 5.4  Isolation results under all source (100/500/1000 ha) and
#           target (25/50/100 ha) patch-size combinations available in the GEE export.
#   R2 5.7  Threshold-specific tables (every value linked to its threshold).
#
# Outputs
#   tableS6a_biome_rank_by_threshold.csv : biome rank (1 = most exposed) in 2022
#                                         for every driver x threshold
#   tableS6b_rank_stability.csv          : Kendall's W (concordance) of biome ranks
#                                         across thresholds, per driver
#   tableS6c_isolation_all_params.csv    : isolation 1986/2022 for all parameter combos
#   figS3_rank_sensitivity.png
# =============================================================================
source(here::here("R", "utils.R"))

exposure <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE) |>
  filter(biome != "Brazil")

ranks <- exposure |> filter(year == CFG$year_end) |>
  group_by(driver, threshold) |>
  mutate(rank = rank(-pct_exposed, ties.method = "min")) |> ungroup()
write_tab(ranks |> select(driver, threshold, biome, pct_exposed, rank), "tableS6a_biome_rank_by_threshold")

# Kendall's W: m raters (thresholds) ranking n objects (biomes); W = 1 means identical rankings
kendall_w <- function(R) {          # R: n objects x m raters matrix of ranks
  n <- nrow(R); m <- ncol(R); Ri <- rowSums(R)
  S <- sum((Ri - mean(Ri))^2); 12 * S / (m^2 * (n^3 - n))
}
stab <- ranks |> group_by(driver) |>
  group_modify(~ {
    R <- .x |> select(biome, threshold, rank) |>
      pivot_wider(names_from = threshold, values_from = rank) |> select(-biome) |> as.matrix()
    tibble(n_thresholds = ncol(R), kendall_W = kendall_w(R),
           top_biome_all_thresholds = paste(unique(.x$biome[.x$rank == 1]), collapse = " / "))
  }) |> ungroup()
write_tab(stab, "tableS6b_rank_stability")

figS3 <- ranks |>
  mutate(biome = factor(biome, levels = rev(CFG$biome_order)),
         driver = factor(driver, levels = CFG$driver_order),
         threshold = factor(threshold, levels = sort(unique(threshold)))) |>
  ggplot(aes(threshold, biome, fill = pct_exposed)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = rank), size = 2.7) +
  scale_fill_gradientn(colours = RColorBrewer_RdPu, name = paste0("% exposed (", CFG$year_end, ")"), trans = "sqrt") +
  facet_wrap(~driver, scales = "free_x", nrow = 1) +
  labs(x = "Threshold", y = NULL, subtitle = "Numbers = biome rank (1 = most exposed)") +
  theme_paper(9) + theme(axis.text.x = element_text(angle = 45, hjust = 1))
save_fig(figS3, "figS3_rank_sensitivity", width = 11, height = 3.6)

if (!file.exists(path_derived("exposure_isolation_all_params.csv"))) {
  message("05: isolation parameters not available for ", CFG$collection, "; Table S6c skipped.")
} else {
iso <- read_csv(path_derived("exposure_isolation_all_params.csv"), show_col_types = FALSE) |>
  filter(year %in% c(CFG$year_start, CFG$year_end)) |>
  select(source_ha, target_ha, threshold_km = threshold, biome, year, pct_exposed) |>
  pivot_wider(names_from = year, values_from = pct_exposed, names_prefix = "pct_") |>
  arrange(biome, source_ha, target_ha, threshold_km)
write_tab(iso, "tableS6c_isolation_all_params")
}
print(stab)
message("05_threshold_sensitivity: done.")
