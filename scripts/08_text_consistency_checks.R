# =============================================================================
# 08_text_consistency_checks.R  ->  outputs/tables/text_numbers_check.csv
#
# Recomputes every number quoted in the Results/Box 1 of the submitted
# manuscript from the pipeline outputs and flags mismatches
# (R2 8.1-8.6, 8.9, 5.7; R1 L277-278, Box 1).
# Rule: each value in the revised text must cite its threshold and come from
# a row of this table (or of Tables S3-S8). Re-run after any data update.
# =============================================================================
source(here::here("R", "utils.R"))

ex <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE)
get_range <- function(drv, bio, yr) {
  d <- ex |> filter(driver == drv, biome == bio, year == yr)
  if (drv == "Fire frequency") d <- d |> filter(threshold == 1)
  sprintf("%.1f-%.1f%%", min(d$pct_exposed), max(d$pct_exposed))
}
get_val <- function(drv, bio, yr, thr, what = "pct_exposed") {
  ex |> filter(driver == drv, biome == bio, year == yr, threshold == thr) |> pull(all_of(what))
}

checks <- tribble(
  ~section,   ~claim_in_manuscript,                           ~driver,               ~biome,            ~year, ~submitted_value,
  "Results",  "Brazil edge 1986 (30-1000 m)",                 "Edge area",           "Brazil",          1986, "3-26%",
  "Results",  "Brazil edge 2022 (30-1000 m)",                 "Edge area",           "Brazil",          2022, "4-33%",
  "Results",  "Brazil small patches 1986",                    "Small-sized patches", "Brazil",          1986, "0.3-1.9%",
  "Results",  "Brazil small patches 2022",                    "Small-sized patches", "Brazil",          2022, "0.4-3%",
  "Results",  "Brazil isolation 1986",                        "Habitat isolation",   "Brazil",          1986, "0.4-1.2%",
  "Results",  "Brazil isolation 2022",                        "Habitat isolation",   "Brazil",          2022, "0.6-2.1%",
  "Results",  "Cerrado edge 1986",                            "Edge area",           "Cerrado",         1986, "9-72%",
  "Results",  "Cerrado edge 2022",                            "Edge area",           "Cerrado",         2022, "11-87%",
  "Results",  "Atlantic Forest edge 2022",                    "Edge area",           "Atlantic Forest", 2022, "26-95%",
  "Results",  "Pampa edge 2022",                              "Edge area",           "Pampa",           2022, "20-96%",
  "Results",  "Atlantic Forest small patches 2022",           "Small-sized patches", "Atlantic Forest", 2022, "3.7-21.8%",
  "Results",  "Atlantic Forest isolation 2022 (R2 8.3)",      "Habitat isolation",   "Atlantic Forest", 2022, "4.9-15%",
  "Results",  "Cerrado isolation 1986",                       "Habitat isolation",   "Cerrado",         1986, "1.2-5%",
  "Results",  "Cerrado isolation 2022",                       "Habitat isolation",   "Cerrado",         2022, "2.5-10%",
  "Results",  "Pampa small patches 1986",                     "Small-sized patches", "Pampa",           1986, "0.7-5%",
  "Results",  "Pampa small patches 2022",                     "Small-sized patches", "Pampa",           2022, "1.7-9.3%"
) |>
  rowwise() |> mutate(recomputed = get_range(driver, biome, year)) |> ungroup()

# Single-threshold claims
single <- tribble(
  ~section, ~claim_in_manuscript, ~submitted_value, ~recomputed,
  "Results", "Brazil forest burned >= 1 time by 2022 ('up to 6%')", "6%",
     sprintf("%.1f%%", get_val("Fire frequency", "Brazil", 2022, 1)),
  "Results", "Pantanal forest burned >= 1 time 1986-2022", "28%",
     sprintf("%.1f%%", get_val("Fire frequency", "Pantanal", 2022, 1)),
  "Results", "Cerrado forest burned >= 1 time 1986-2022", "19%",
     sprintf("%.1f%%", get_val("Fire frequency", "Cerrado", 2022, 1)),
  "Results", "Amazon forest burned >= 1 time, area ('at least 16.2 Mha in 40 years')", "16.2 Mha",
     sprintf("%.1f Mha", get_val("Fire frequency", "Amazon", 2022, 1, "area_exposed_ha") / 1e6),
  "Results", "Amazon edge area 1986, absolute (30-1000 m)", "2-55 Mha",
     with(ex |> filter(driver == "Edge area", biome == "Amazon", year == 1986),
          sprintf("%.1f-%.1f Mha", min(area_exposed_ha) / 1e6, max(area_exposed_ha) / 1e6)),
  "Results", "Amazon edge area 2022, absolute (30-1000 m)", "5-73 Mha",
     with(ex |> filter(driver == "Edge area", biome == "Amazon", year == 2022),
          sprintf("%.1f-%.1f Mha", min(area_exposed_ha) / 1e6, max(area_exposed_ha) / 1e6))
)

out <- bind_rows(checks |> select(section, claim_in_manuscript, submitted_value, recomputed), single) |>
  rowwise() |>
  mutate(max_abs_diff = {
    a <- as.numeric(regmatches(submitted_value, gregexpr("[0-9.]+", submitted_value))[[1]])
    b <- as.numeric(regmatches(recomputed, gregexpr("[0-9.]+", recomputed))[[1]])
    if (length(a) == length(b)) max(abs(a - b)) else NA_real_ }) |>
  ungroup() |>
  # tolerance 0.5 (rounding in the text); anything above must be corrected in the text
  mutate(status = ifelse(!is.na(max_abs_diff) & max_abs_diff <= 0.5, "OK (rounding)", "MISMATCH - correct text"))
write_tab(out, "text_numbers_check")
print(out, n = 50, width = 200)
message("08_text_consistency_checks: done. Compare columns 'submitted_value' and 'recomputed'.")
