# =============================================================================
# 07_forest_type_ranking.R  ->  Figure 4 / Box 1 (revised), Table S8 (new)
#
# Addresses:
#   R2 1.6  "Red List" renamed to "exposure ranking" of forest types.
#   R2 6.5  Ranking method made explicit: reference year 2022, literature-based
#           scenario (edge <= 150 m, patches <= 50 ha, isolation >= 5 km, >= 1 fire),
#           equal weights; sensitivity to (i) leave-one-driver-out, (ii) rank-sum vs
#           mean-% aggregation, (iii) reference year 2010.
#   R1 Box 1 / R2 8.9  Sequential colour scale (RdPu) instead of Spectral; caption
#           written once.
#   R1 Box 1  "edge effects affected 8%" now states the distance (<= 150 m).
#
# Input: data/raw/ibge_vegetation/ - area by IBGE vegetation type (id_class) and
# by EXCLUSIVE threshold class (e.g. edge class 60 = 30-60 m), computed in GEE with
# gee/submitted_col9/getArea_IBGE.js (forest mask = MapBiomas classes 3, 5, 6, 49
# of each year, intersected with the IBGE potential vegetation map rasterized at 30 m).
#
# Replaces: 0*_graphics*_IBGE.R, 07_plotFigRankBox.R, 07_plotFigRankBox_heatMap.R.
# NOTE: the submitted rank tables used isolation and fire with ALL classes summed;
# here the same definition is reproduced and made explicit (isolation: any class
# >= 5 km; fire: >= 1 fire), so the numbers should match Figure 4.
# =============================================================================
source(here::here("R", "utils.R"))

lk <- read_csv(path_raw("ibge_vegetation", "ibge_vegetation_lookup.csv"), show_col_types = FALSE)
forest_types <- c(
  "Floresta Estacional Semidecidual" = "SSF - Semideciduous Seasonal Forest",
  "Floresta Ombrófila Mista"         = "MOF - Mixed Ombrophilous Forest",
  "Floresta Estacional Decidual"     = "DSF - Deciduous Seasonal Forest",
  "Floresta Ombrófila Densa"         = "DOF - Dense Ombrophilous Forest",
  "Floresta Ombrófila Aberta"        = "OOF - Open Ombrophilous Forest",
  "Floresta Estacional Sempre-Verde" = "ESF - Evergreen Seasonal Forest")

rd <- function(x) read_csv(path_raw("ibge_vegetation", paste0("area_", x, "_ibge_c9.csv")),
                           show_col_types = FALSE) |> select(territory, year, class_id, area)
ref <- rd("reference") |> select(territory, year, forest_ha = area)

sc <- CFG$scenario
exp_type <- bind_rows(
  rd("edge")      |> filter(class_id <= sc$edge)  |> mutate(driver = "Edge area"),
  rd("patch")     |> filter(class_id <= sc$patch) |> mutate(driver = "Small-sized patches"),
  rd("isolation") |> filter(class_id >= sc$isolation) |> mutate(driver = "Habitat isolation"),
  rd("firecount") |> filter(class_id >= sc$fire)  |> mutate(driver = "Fire frequency")) |>
  group_by(territory, year, driver) |> summarise(exposed_ha = sum(area)) |> ungroup() |>
  left_join(ref, by = c("territory", "year")) |>
  left_join(lk, by = c("territory" = "id_class")) |>
  mutate(pct = 100 * exposed_ha / forest_ha)

write_tab(exp_type |> arrange(legenda_1, driver, year), "tableS8a_exposure_by_ibge_vegetation_type")

rank_types <- function(d, drivers = CFG$driver_order) {
  d |> filter(driver %in% drivers) |>
    group_by(driver) |> mutate(r = rank(-pct)) |>
    group_by(legenda_1) |> summarise(mean_pct = mean(pct), rank_sum = sum(r)) |>
    mutate(rank_mean_pct = rank(-mean_pct), rank_rank_sum = rank(rank_sum))
}
ft <- exp_type |> filter(legenda_1 %in% names(forest_types)) |>
  mutate(type = forest_types[legenda_1])

base22 <- rank_types(ft |> filter(year == 2022)) |> mutate(scenario = "2022, equal weights")
sens <- bind_rows(
  base22,
  rank_types(ft |> filter(year == 2010)) |> mutate(scenario = "2010, equal weights"),
  purrr::map_dfr(CFG$driver_order, \(drop)
    rank_types(ft |> filter(year == 2022), setdiff(CFG$driver_order, drop)) |>
      mutate(scenario = paste("2022, without", drop))))
write_tab(sens |> mutate(type = forest_types[legenda_1]), "tableS8b_ranking_sensitivity")

# Figure 4 (revised)
d4 <- ft |> filter(year == 2022) |>
  left_join(base22 |> select(legenda_1, mean_pct), by = "legenda_1") |>
  mutate(type = forcats::fct_reorder(type, mean_pct),
         driver = factor(driver, levels = CFG$driver_order))
fig4 <- ggplot(d4, aes(driver, type, fill = pct)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.1f", pct), colour = pct > 40), size = 3) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "grey15"), guide = "none") +
  scale_fill_gradientn(colours = RColorBrewer_RdPu, limits = c(0, 100), name = "% of forest\nexposed (2022)") +
  scale_x_discrete(labels = c("Edge area\n(≤ 150 m)", "Small-sized patches\n(≤ 50 ha)",
                              "Habitat isolation\n(≥ 5 km)", "Fire\n(≥ 1 since 1985)")) +
  labs(x = NULL, y = NULL) + theme_paper(10) + theme(legend.position = "right")
save_fig(fig4, "fig4_forest_type_exposure_ranking", width = 8, height = 4)
print(sens |> select(scenario, legenda_1, rank_mean_pct) |>
        pivot_wider(names_from = scenario, values_from = rank_mean_pct))
message("07_forest_type_ranking: done.")
