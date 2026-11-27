# Isolation, Collection 11: changes from the original GEE code

Original code: the 5 JavaScript scripts of the v6/v7 isolation workflow (LULC Collection 8,
1985–2022, `projects/mapbiomas-workspace/DEGRADACAO/ISOLATION/`).
Port: `isolation_col11.py` (LULC Collection 11, 1986–2024,
`projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/isolation/`).

Each change is marked `# CHANGE:` in the code or is a configurable option in `Config`.

## Kept identical (defaults)

| Element | Original | Port (default) |
|---|---|---|
| Working grid | 100 m, `reproject('epsg:4326', null, 100)`, pyramiding `mode` | same (`crs="EPSG:4326"`, `scale=100`) |
| Patch size | `connectedPixelCount(1024, true)` (8-neighbour) on 100 m masks; 1 px ≈ 1 ha | same |
| "Forest" mask | classes 3, 4, 5, 6, 11, 12, 49, 50 | same (`forest_bin_classes`) |
| Natural mask | 3, 4, 5, 6, 49, 11, 12, 13, 29, 32, 50, 23 (+33) | same, except water (see change 1) |
| Sources | natural `conect >= 100 / 500 / 1000` | same |
| Distance | `distance(ee.Kernel.euclidean(25000, 'meters'))`, 25001 where no source | same |
| Targets | (forest conect ≤ T) OR (natural conect ≤ T), T = 25 / 50 / 100; `connectedComponents(Kernel.plus(1), maxSize 550)` | same (`target_connectedness="plus"`) |
| Isolation rule | minimum distance over the target patch `> 5 / 10 / 20 km` (`reduceConnectedComponents(min, 256)`) | same |
| Combinations | 24 (target 100 × source 100 skipped) | same (`skip_source_le_target=True`) |
| "Uso" output | LULC class of isolated pixels, classes 3, 4, 5, 6, 49 (forest) + 11, 12, 32, 29, 50 (non-forest) | same (`uso_classes`) |

## Changes

1. **Water as natural only in the Pantanal** (`water_as_natural="pantanal"`). The v6 code included
   water (33) in the natural mask of every biome, so rivers and reservoirs were part of source
   patches and could bridge targets. The current module (script 05a, Collection 10.1) and ATBD v2
   §2.6 restrict this to the Pantanal. Set `"all"` to reproduce the v6 behaviour. *(R2 7.1)*
2. **Period and data**: LULC Collection 11, 1986–2024 (was Collection 8, 1985–2022).
3. **Outputs organised per year** in four ImageCollections (`masks_100m_v1`, `conn_100m_v1`,
   `distance_100m_v1`, `isolation_100m_v1`) instead of multi-year multi-band images. Same content
   (`isolation_<year>` has the 24 `uso_t{T}_s{S}_d{D}` bands = the 24 `nat_uso_frag*` assets of the
   original, one band per combination). Per-year exports run in parallel and fail independently.
4. **Steps D and E merged**: the binary `frag*_dist*` assets were only used to mask the LULC in
   step E; the port writes the class directly (isolated ⇔ band > 0). Saves 24 intermediate assets per run.
5. **New stage S5 (statistics)**: forest area (classes 3, 5, 6, 49 of the **30 m** Collection 11 map,
   `pixelArea()` in ha) inside isolated targets, by biome × LULC class, for the 24 combinations plus
   the forest reference area, in one grouped `reduceRegion` per year. Exported as table assets and
   CSV (Drive) and read by `R/utils.R::read_isolation_col11()`.
6. **Distance export pyramiding** `mean` instead of `mode` (continuous variable; only affects
   zoomed-out display, not values at 100 m).

## Points that remain as in the original and should be described in the paper (R2 3.1–3.3)

* **1,024-pixel limit**: at 100 m one pixel ≈ 1 ha, so sources ≥ 1,000 ha (1,000 px) are
  identified below the limit; patches > 1,024 px are counted as 1,024, which does not affect any
  threshold used (all ≤ 1,000 px).
* **Pixel area in EPSG:4326**: at "100 m" in geographic coordinates a pixel is ≈ 1 ha × cos(latitude)
  (≈ 0.87 ha at 30° S), so "100 / 500 / 1000 ha" are pixel counts, slightly smaller in true area in
  the south. Distances from `distance()` are in metres and are not affected.
* **Connectivity**: patch sizes use 8-neighbour connectivity, target components use 4-neighbour
  (`Kernel.plus`). A diagonal-only link therefore joins two pixels for the size but not for the
  minimum-distance grouping. Set `target_connectedness="square"` to make both 8-neighbour.
* **"Forest" mask** of the original code includes wetland (11), grassland (12) and herbaceous sandbank (50);
  it is used only to define target patches together with the natural mask, never as the paper's forest.
* **Cross-border sources** are not considered (the LULC map ends at the border).

## Alternatives not adopted by default

* `connectedPixelCount` → module patch-size asset (GRASS `r.clump`, true area, no pixel limit).
  Would align isolation with the patch-size metric of the 11.1a tables but changes the method
  described in the ATBD. Can be added as an option if the authors prefer.
* Metric projection (EPSG:5880) for the 100 m grid: removes the cos(latitude) effect above; set
  `crs="EPSG:5880"` in `Config` (all stages use `cfg.crs`).
