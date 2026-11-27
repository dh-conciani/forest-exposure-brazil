# SYNTHETIC isolation CSVs in the format of gee/col11/isolation_forest_col11.js (TEST ONLY).
# Usage: Rscript tests/make_synthetic_isolation.R /tmp/iso  (never into data/raw/)
# Then copy the repo, put the CSVs in data/raw/col11/isolation/ of the copy and run run_all.R.
suppressMessages(library(dplyr))
out <- commandArgs(TRUE)[1]; dir.create(out, FALSE, TRUE)
ex <- readr::read_csv(here::here("data", "derived", "col11", "exposure_biome.csv"), show_col_types=FALSE) |>
  filter(driver=="Edge area", threshold==30, biome!="Brazil") |> distinct(biome, year, area_forest_ha)
code <- c(Amazon=1, Caatinga=2, Pantanal=3, Cerrado=4, `Atlantic Forest`=5, Pampa=6)
set.seed(1)
for (y in 1986:2024) {
  e <- ex |> filter(year==y)
  ref <- bind_rows(lapply(seq_len(nrow(e)), function(i) tibble(year=y, territory=code[e$biome[i]]*100+c(3,5,6,49),
          source_ha=0, target_ha=0, dist_class=0, area_ha=e$area_forest_ha[i]*c(.9,.03,.05,.02))))
  rows <- list()
  for (s in c(100,500,1000)) for (t in c(25,50,100)) {
    base <- 0.002*(1+(y-1986)/40)*(s/1000)^.3*(t/100)^.5
    rows[[length(rows)+1]] <- ref |> select(year, territory, area_ha) |>
      tidyr::crossing(dist_class=c(500,1000,2000,5000,10000)) |>
      mutate(source_ha=s, target_ha=t, area_ha=area_ha*base*c(`500`=.4,`1000`=.25,`2000`=.15,`5000`=.12,`10000`=.08)[as.character(dist_class)])
  }
  readr::write_csv(bind_rows(ref, bind_rows(rows)) |> select(year,territory,source_ha,target_ha,dist_class,area_ha),
                   file.path(out, paste0("isolation_forest_col11_", y, ".csv")))
}
