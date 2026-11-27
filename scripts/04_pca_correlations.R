# =============================================================================
# 04_pca_correlations.R  ->  Figure 3 (revised), Table S5, Figure S2 (revised)
#
# Addresses R2 6.1, 6.2, 1.2, 1.5, 8.1, 8.9 (remove Brazil from PCA).
#
# Submitted version (09_correlationVectors.R):
#   prcomp(..., scale. = FALSE) on % exposed, Brazil included as a 7th "biome",
#   pooled across biomes and years. Unscaled PCA is dominated by the variable with
#   the largest variance (edge area), which explains why PC1 ~ "fragmentation"
#   carried 92% of the variance; Brazil duplicates the biomes (pseudo-replication).
#
# Revised analysis:
#   (A) Spatial structure  : PCA on standardized variables, biomes only (6 x 37 obs).
#   (B) Temporal covariation: PCA on variables centered AND scaled WITHIN each
#       biome, which removes between-biome differences and keeps only the joint
#       temporal variation (R2 6.1 "centering values within biomes").
#   (C) Correlations: Pearson on raw series AND on first differences (year-to-year
#       changes), per biome, with p-values; shared monotonic trends inflate raw r
#       (R2 6.2).
#   Explained variance is reported as covariation, not as "driver contribution".
#   Fire is excluded from (B)/(C)-differences sensitivity runs because it is
#   cumulative (see 03_trends_rates.R); results with and without fire are saved.
# =============================================================================
source(here::here("R", "utils.R"))
library(patchwork)

sc <- CFG$scenario
wide <- read_csv(path_derived("exposure_biome.csv"), show_col_types = FALSE) |>
  filter(biome != "Brazil",
         (driver == "Edge area" & threshold == sc$edge) |
         (driver == "Small-sized patches" & threshold == sc$patch) |
         (driver == "Habitat isolation" & threshold == sc$isolation) |
         (driver == "Fire frequency" & threshold == sc$fire)) |>
  select(biome, year, driver, pct_exposed) |>
  pivot_wider(names_from = driver, values_from = pct_exposed) |>
  mutate(biome = factor(biome, levels = CFG$biome_order))
vars <- CFG$driver_order

run_pca <- function(X, label) {
  p <- prcomp(X, center = TRUE, scale. = TRUE)
  list(pca = p, label = label,
       var = tibble(analysis = label, PC = paste0("PC", seq_along(p$sdev)),
                    var_explained = p$sdev^2 / sum(p$sdev^2)),
       load = as_tibble(p$rotation[, 1:2], rownames = "driver") |> mutate(analysis = label))
}

# (A) between-biome + temporal, standardized
pA <- run_pca(wide[, vars], "A_standardized_pooled")
# (B) within-biome centered and scaled (temporal covariation only)
within <- wide |> group_by(biome) |>
  mutate(across(all_of(vars), ~ (.x - mean(.x)) / sd(.x))) |> ungroup()
pB <- run_pca(within[, vars], "B_within_biome")
# (B2) same without fire (cumulative metric)
pB2 <- run_pca(within[, setdiff(vars, "Fire frequency")], "B2_within_biome_no_fire")

write_tab(bind_rows(pA$var, pB$var, pB2$var), "tableS5a_pca_variance")
write_tab(bind_rows(pA$load, pB$load, pB2$load), "tableS5b_pca_loadings")

biplot <- function(res, data) {
  sc_ <- as_tibble(res$pca$x[, 1:2]) |> bind_cols(data |> select(biome, year))
  ld <- res$load; k <- max(abs(sc_$PC1), abs(sc_$PC2)) / max(abs(ld$PC1), abs(ld$PC2)) * 0.8
  ve <- round(100 * res$var$var_explained[1:2], 1)
  ggplot(sc_, aes(PC1, PC2, colour = biome)) +
    geom_hline(yintercept = 0, colour = "grey85") + geom_vline(xintercept = 0, colour = "grey85") +
    geom_path(alpha = 0.5) + geom_point(aes(alpha = year), size = 1.2) +
    geom_segment(data = ld, aes(0, 0, xend = PC1 * k, yend = PC2 * k), inherit.aes = FALSE,
                 arrow = arrow(length = unit(0.15, "cm")), colour = "grey20") +
    ggrepel::geom_label_repel(data = ld, aes(PC1 * k, PC2 * k, label = driver), inherit.aes = FALSE,
              size = 2.6, colour = "grey20", fill = "white", label.size = 0, min.segment.length = 1) +
    scale_colour_brewer(palette = "Dark2", name = NULL) +
    scale_alpha_continuous(range = c(0.25, 1), breaks = c(1986, 2004, 2022), name = "Year") +
    labs(x = paste0("PC1 (", ve[1], "%)"), y = paste0("PC2 (", ve[2], "%)")) +
    theme_paper(9)
}
fig3 <- (biplot(pA, wide) + labs(tag = "a", title = "Standardized, biomes pooled")) +
        (biplot(pB, within) + labs(tag = "b", title = "Centered and scaled within biome")) +
        plot_layout(guides = "collect") & theme(legend.position = "bottom")
save_fig(fig3, "fig3_pca_revised", width = 10, height = 5.2)

# (C) correlations: raw vs first differences
pair_cor <- function(d, lab) {
  cmb <- utils::combn(vars, 2)
  purrr::map_dfr(seq_len(ncol(cmb)), function(j) {
    a <- d[[cmb[1, j]]]; b <- d[[cmb[2, j]]]
    ok <- is.finite(a) & is.finite(b)
    if (sum(ok) < 5 || sd(a[ok]) == 0 || sd(b[ok]) == 0) return(NULL)
    ct <- cor.test(a[ok], b[ok], method = "pearson")
    tibble(series = lab, var1 = cmb[1, j], var2 = cmb[2, j], r = unname(ct$estimate),
           p_value = ct$p.value, n = sum(ok))
  })
}
cors <- wide |> arrange(biome, year) |> group_by(biome) |>
  group_modify(~ bind_rows(
    pair_cor(.x, "raw"),
    pair_cor(.x |> mutate(across(all_of(vars), ~ c(NA, diff(.x)))), "first_differences"))) |>
  ungroup() |> mutate(p_adj_BH = p.adjust(p_value, "BH"))
write_tab(cors, "tableS5c_correlations_raw_vs_diff")

figS2 <- cors |>
  mutate(pair = paste(var1, "×", var2),
         series = factor(series, c("raw", "first_differences"), c("Raw series", "First differences")),
         sig = ifelse(p_adj_BH < 0.05, "*", "")) |>
  ggplot(aes(biome, pair, fill = r)) + geom_tile(colour = "white") +
  geom_text(aes(label = paste0(sprintf("%.2f", r), sig)), size = 2.6) +
  scale_fill_distiller(palette = "RdBu", limits = c(-1, 1), direction = 1) +
  facet_wrap(~series) + labs(x = NULL, y = NULL, fill = "Pearson r") +
  theme_paper(9) + theme(axis.text.x = element_text(angle = 30, hjust = 1))
save_fig(figS2, "figS2_correlations_raw_vs_diff", width = 10, height = 4.2)
print(bind_rows(pA$var, pB$var, pB2$var) |> filter(PC %in% c("PC1", "PC2")))
message("04_pca_correlations: done.")
