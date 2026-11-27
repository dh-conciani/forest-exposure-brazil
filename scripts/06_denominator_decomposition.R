# =============================================================================
# 06_denominator_decomposition.R  ->  Table S7 (new)
#
# Addresses R2 5.5 (first part): "Assess how deforestation and regeneration alter
# the proportion of exposed forest independently of changes in exposure."
#
# The proportion p = E / F (E = exposed area, F = forest area). Its log-change
# between 1986 and 2022 decomposes exactly as
#     ln(p22/p86) = ln(E22/E86)  -  ln(F22/F86)
#                   [numerator]     [denominator]
# The share of the change in p explained by the shrinking forest denominator is
#     -ln(F22/F86) / ln(p22/p86).
# If a large share comes from the denominator, the increase in % exposed is
# driven by forest loss rather than by more forest becoming exposed.
#
# The complementary test with a FIXED stable-forest mask (forest in all years
# 1986-2022) requires new GEE exports - see docs/gee_new_runs.md (run G1).
# =============================================================================
source(here::here("R", "utils.R"))

sc <- CFG$scenario
x <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE) |>
  filter((driver == "Edge area" & threshold == sc$edge) |
         (driver == "Small-sized patches" & threshold == sc$patch) |
         (driver == "Habitat isolation" & threshold == sc$isolation) |
         (driver == "Fire frequency" & threshold == sc$fire),
         year %in% c(CFG$year_start, CFG$year_end)) |>
  select(driver, biome, year, E = area_exposed_ha, F = area_forest_ha, p = pct_exposed) |>
  pivot_wider(names_from = year, values_from = c(E, F, p))

dec <- x |>
  mutate(log_change_p = log(p_2022 / p_1986),
         log_change_E = log(E_2022 / E_1986),
         log_change_F = log(F_2022 / F_1986),
         forest_change_pct = 100 * (F_2022 / F_1986 - 1),
         share_from_denominator = ifelse(is.finite(log_change_p) & abs(log_change_p) > 1e-6,
                                         -log_change_F / log_change_p, NA_real_)) |>
  arrange(driver, biome)
write_tab(dec, "tableS7_denominator_decomposition")
print(dec |> select(driver, biome, p_1986, p_2022, forest_change_pct, share_from_denominator), n = 30)
message("06_denominator_decomposition: done.")
