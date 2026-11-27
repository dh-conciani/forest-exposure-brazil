# =============================================================================
# 09_edge_age.R  ->  Figure S4 (new), Table S9 (new)   [Collection 11 only]
#
# Addresses R2 5.6 ("justify treating all edges equally despite differences in
# ... edge age") and R1 (edge influence differs with edge history).
# The 11.1a edge table holds, for every distance threshold, the forest area by
# edge age (number of consecutive years the pixel has been edge; ATBD v2 2.5).
# We report, for the scenario distance (<= 150 m), the share of edge forest in
# age classes 1-5, 6-10, 11-20 and > 20 years, by biome and year.
# =============================================================================
source(here::here("R", "utils.R"))
if (CFG$collection != "col11") {
  message("09: edge age only exists in the col11 tables.")
} else {
  e <- read_mb_xlsx(path_raw("col11", "brazil-refined-biome-edges-11.1a.xlsx")) |>
    filter(key == "value", as.numeric(edge_size) == CFG$scenario$edge) |>
    mutate(edge_age = as.numeric(edge_age),
           age_class = cut(edge_age, c(0, 5, 10, 20, Inf), labels = c("1-5", "6-10", "11-20", ">20"))) |>
    group_by(biome, year, age_class) |> summarise(area_ha = sum(area_ha, na.rm = TRUE)) |>
    ungroup()
  e <- bind_rows(e, e |> group_by(year, age_class) |> summarise(area_ha = sum(area_ha)) |> mutate(biome = "Brazil")) |>
    group_by(biome, year) |> mutate(share = 100 * area_ha / sum(area_ha)) |> ungroup() |>
    mutate(biome = factor(biome, levels = c("Brazil", CFG$biome_order)))
  write_tab(e, "tableS9_edge_age_150m")

  # Edge age is truncated by the start of the series (max age in year t = t - 1985 + 1);
  # only years >= 2006 allow ">20" and are interpreted.
  figS4 <- ggplot(e |> filter(year >= 2006), aes(year, share, fill = age_class)) +
    geom_area() + facet_wrap(~biome, nrow = 1) +
    scale_fill_manual(values = seq_pal(4), name = "Edge age (years)") +
    labs(x = NULL, y = "% of forest edge area (≤ 150 m)") + theme_paper(9)
  save_fig(figS4, "figS4_edge_age", width = 10, height = 3.4)
  print(e |> filter(year == CFG$year_end) |> select(biome, age_class, share) |>
          tidyr::pivot_wider(names_from = age_class, values_from = share))
}
