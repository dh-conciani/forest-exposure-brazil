# Collection 11 — GEE steps for the paper

The MapBiomas Degradation Module tables `*-11.1a.xlsx` (edge area + edge age, patch size,
fire frequency, secondary vegetation; 1985–2025) are used directly from `data/raw/col11/`.
Habitat isolation is **not** in those tables and is produced by `isolation_forest_col11.js`.

## isolation_forest_col11.js

* Follows ATBD v2 §2.6 (targets ≤ 25/50/100 ha, sources ≥ 100/500/1000 ha, ≥ 5/10/20 km).
* Uses the module **patch-size asset** (GRASS `r.clump`, 8-neighbour, true area) → no
  `connectedPixelCount()` 1,024-pixel limit (R2 3, 3.2, 3.3).
* Distance with `fastDistanceTransform` at 100 m in **EPSG:5880** (metric, equal at all latitudes; R2 3.1).
* Patch-level distance = minimum over the target patch (100 m components, 8-neighbour).
* Output: one CSV per year → `data/raw/col11/isolation/`. Columns
  `year, territory (= biome*100 + LULC class), source_ha, target_ha, dist_class, area_ha`;
  `dist_class` is exclusive (5 = 5–10 km, 10 = 10–20 km, 20 = ≥ 20 km; 0 = forest reference).
  `R/utils.R::read_isolation_col11()` converts it to cumulative thresholds.

### Before running
1. Fill the `TODO` asset ids (LULC Collection 11 and the Collection 11 patch-size asset).
2. Confirm the biome codes of `biomas-raster-41` and update `biome_code` in `R/utils.R`
   (the module scripts use 3 = Pantanal; the others are placeholders).
3. Pantanal: the Collection 9 workflow treated water as native for patches/isolation. Check
   whether the Collection 11 patch-size asset already does; if not, isolation in the Pantanal
   will count flooding as fragmentation (R2 7.1).
4. Test with `years: [2022]` first, check the console and the two map layers, then run all years.
