# =============================================================================
# 02_fig1_timeseries.R  ->  Figure 1 (revised)
# Temporal trajectories of the % of forest exposed to each driver, by biome,
# for every threshold.
#
# Changes requested in review:
#   R1  (Fig. 1, Fig. 2): sequential colour scale (ColorBrewer RdPu) instead of a
#       categorical one, because thresholds are ordered quantitative classes.
#   R2 8.9: legend classes written as cumulative thresholds (<= 30 m, <= 60 m ...),
#       so there are no overlapping intervals (submitted version used
#       "151-300", "301-600", "600-1000").
#   R2 1.4: thresholds are referred to as "thresholds" (multi-threshold), not "scales".
#   One facet row per driver with a free y-axis, so that low-exposure drivers
#   (isolation, fire) are legible.
# Replaces: 07_plotFig1.R, 07_plotFig1_v2.R and the plotting part of scripts 01-04.
# =============================================================================
source(here::here("R", "utils.R"))
library(patchwork)

exposure <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE) |>
  mutate(biome = factor(biome, levels = c("Brazil", CFG$biome_order)))

unit_lab <- c("Edge area" = "Distance to edge (m)", "Small-sized patches" = "Patch size (ha)",
              "Habitat isolation" = "Distance to source patch (km)",
              "Fire frequency" = "Number of fires since 1985")
prefix   <- c("Edge area" = "≤ ", "Small-sized patches" = "≤ ",
              "Habitat isolation" = "≥ ", "Fire frequency" = "≥ ")
# Thresholds shown for fire (all 1..10 are in the data; 1, 2, 3, 5, 10 shown for legibility)
fire_show <- c(1, 2, 3, 5, 10)

panel <- function(drv, tag) {
  d <- exposure |> filter(driver == drv)
  if (drv == "Fire frequency") d <- d |> filter(threshold %in% fire_show)
  thr <- sort(unique(d$threshold))
  # order colours so that the most "severe" class is darkest
  severe_first <- drv %in% c("Edge area", "Small-sized patches")
  pal <- seq_pal(length(thr)); if (severe_first) pal <- rev(pal)
  d <- d |> mutate(thr_f = factor(threshold, levels = thr,
                                  labels = paste0(prefix[drv], thr)))
  ggplot(d, aes(year, pct_exposed, colour = thr_f, group = thr_f)) +
    geom_line(linewidth = 0.55) +
    facet_wrap(~biome, nrow = 1) +
    scale_colour_manual(values = pal, name = unit_lab[drv]) +
    scale_x_continuous(breaks = c(1990, 2005, 2020)) +
    labs(x = NULL, y = "% of forest exposed", tag = tag, title = drv) +
    theme_paper(9) +
    theme(legend.position = "right", legend.key.height = unit(0.35, "cm"),
          plot.title = element_text(size = 9, face = "bold"))
}

drivers <- intersect(CFG$driver_order, unique(exposure$driver))   # isolation may be missing (col11)
fig1 <- patchwork::wrap_plots(purrr::map2(drivers, letters[seq_along(drivers)], panel), ncol = 1)
save_fig(fig1, "fig1_exposure_timeseries", width = 10, height = 2.25 * length(drivers))
message("02_fig1_timeseries: done.")
