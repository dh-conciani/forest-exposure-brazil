# New GEE exports needed for the revision

Analyses below cannot be done with the existing tables. Each run must export a CSV with the
same structure as `data/raw/biome/*.csv` (or the long format of `getArea_IBGE.js`) into
`data/raw/revision/`, and is then read by a new R script (numbers reserved below).

| Run | Purpose | Comments | What to export | R script |
|---|---|---|---|---|
| **G1** Stable-forest mask | Separate change in exposure from change in the forest denominator | R2 5.5, 7.1 (Atlantic Forest) | Same four drivers, but area computed only inside pixels that are forest in **all** years 1986–2022 (`forest_1986 AND … AND forest_2022`). Denominator = stable forest area (constant). | `09_stable_forest.R` |
| **G2** Annual burned forest | Annual (non-cumulative) fire metric, for trends and correlations | R2 3.4, 6.2, 8.6 | Per biome × year: forest area burned in year *t* (fire_t AND forest_t) and total burned area in year *t* (all classes). | `10_fire_annual.R` |
| **G3** Projection / pixel-size check | Effect of EPSG:4326 pixel geometry on edge distances and patch areas | R2 3.1, 3.2 | For 2022 only: (a) edge ≤ 30/60/150 m recomputed after `reproject` to an equal-area CRS (e.g. SIRGAS 2000 / Brazil Polyconic, EPSG:5880) at 30 m; (b) patch size with threshold in **true area** (`pixelArea` summed with `reduceConnectedComponents`) instead of pixel count. | `11_projection_check.R` |
| **G4** Small-patch noise | Classification noise in very small patches | R2 2.3, 5.4 | Patch tables recomputed excluding patches < 0.5 ha and < 1 ha (FAO minimum area), 2022 and 1986. | `12_small_patch_noise.R` |
| **G5** Accuracy by biome | Report forest-class accuracy by biome | R2 2.3 | No new export: copy user's/producer's accuracy of the forest classes per biome from the MapBiomas Col. 9 accuracy statistics (level 1 and level 3). | table only |
| **G6** Protected forests | Support the "37 % of forests protected" claim | R2 8.8 | Forest area 2022 inside Conservation Units (CNUC/MMA, reference date) and Indigenous Lands (FUNAI, reference date), by biome, no double counting of overlaps. | `13_protected.R` |
| **G7** Edge by adjacent land use (optional) | Address "all edges treated equally" | R2 5.6, R1 | Edge ≤ 150 m split by the class of the nearest anthropogenic pixel (pasture, agriculture, urban, mining, other). | `14_edge_by_landuse.R` |

Priority (by impact on the reviewers' main concerns and by deadline, 18 Dec 2026):
G2 → G1 → G3 → G6 → G4 → G7. G5 needs no processing.
