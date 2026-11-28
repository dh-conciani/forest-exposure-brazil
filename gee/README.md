# Google Earth Engine scripts — what was run for the paper

The R pipeline starts from area tables exported from GEE (`data/raw/`). This folder documents the
GEE side so that Methods, code and outputs match (Reviewer 2, comments 2.1, 3.1–3.5, 4.1).

## Provenance

The scripts in `submitted_col9/` were copied from
`mapbiomas/brazil-degradation` @ `b45a9c8d41f09114e2f80e827c8529567361ddab` (folder `old/`), which
holds the Collection 9 versions. The root of that repository is the **operational** Degradation
Module (Collection 10.1, Fire 4.1, edge up to 7 km, isolation at 100 m with R/GRASS patch
workflow) and was **not** used in the paper. That mismatch is what Reviewer 2 (2.1) observed.

> ⚠️ To confirm by the authors before freezing the release (see `docs/revision_tracker.csv`, items marked `CONFIRM`):
> 1. `07_fire_frequency.js` in `old/` already points to LULC Col. 10.1 and Fire Col. 4.1, but the
>    exported table used in the paper is `brazil-refined-biome-fire-9.0.1a.csv`. Which Fire
>    collection produced it (Col. 3 as stated in the Methods, or 4.1)? Commit the exact script.
> 2. Commit the "summary" scripts that produced the assets read by `getArea_IBGE.js`
>    (`projects/mapbiomas-workspace/DEGRADACAO/COLECAO/BETA/PROCESS/summary/*_col9_v1`).
> 3. Commit the script that produced the biome statistics tables (`brazil-refined-biome-*-9.0.1a.csv`).
> 4. Isolation steps A–C (100 m masks, `connectedPixelCount`, distances) for Col. 9 are missing in
>    `old/`; only steps D–F are there.

## Inputs

| Input | Asset | Version |
|---|---|---|
| LULC | `projects/mapbiomas-public/assets/brazil/lulc/collection9/mapbiomas_collection90_integration_v1` | Col. 9, 1985–2023 |
| Biomes | `projects/mapbiomas-workspace/AUXILIAR/biomas-2019-raster` | IBGE 2019, 1:250,000 |
| IBGE vegetation | `projects/mapbiomas-territories/assets/TERRITORIES/LULC/BRAZIL/COLLECTION9/WORKSPACE/INFORMACAO_AMBIENTAL_VEGETACAO_IBGE_raster` | IBGE potential vegetation (1:250,000), rasterized on the MapBiomas grid |
| Fire | MapBiomas Fire (cited as Collection 3 in the submitted manuscript) | — |

Grid: all MapBiomas assets are in EPSG:4326 with a pixel of 0.00026949° (≈ 30 m at the Equator).
In geographic coordinates the east–west pixel size shrinks with latitude (≈ 26 m at 30° S).

## Parameters per driver (as coded)

### Edge area — `01_fragmentation_edgeArea.js`
* Native classes (no edge between them): 3, 4, 5, 6 (Amazon only), 11, 12, 49, 50. Anthropogenic = everything else, remapped to 21.
* Classes that never receive edge: 13, 29, 32, 33 (other non-forest, rocky outcrop, hypersaline tidal flat, water).
* `anthropogenic.distance(ee.Kernel.euclidean(d + 10, 'meters'), false)` then `edge.lt(d)`, for d ∈ {30, 60, 90, 120, 150, 300, 600, 1000}.
* Distance is between pixel centres, computed in the pixel grid of the input (EPSG:4326). Consequence: the "≤ 30 m" class holds the 4-neighbour forest pixels adjacent to anthropogenic pixels (diagonals are ≈ 42 m and excluded); because east–west spacing shrinks with latitude, a fixed metric threshold covers slightly more pixels at high latitudes (R2 3.1). Quantified in run **G3** of `docs/gee_new_runs.md`.
* Export: `scale: 30`, one asset per distance (`edge_<d>m_col9_v<version>`).

### Small-sized patches — `02_fragmentation_patchSize.js`
* Patch = connected native vegetation (all native classes above dissolved; Pantanal also includes water, 33), **8-neighbour** (`connectedPixelCount(maxSize, true)`).
* Size threshold in pixels: `size_px = floor(ha × 10 000 / 900)`; `maxSize = size_px + 5` (≤ 838 px for 75 ha, below the 1024-pixel limit of `connectedPixelCount`). The submitted text wrongly states that 1024 px ≈ 75 ha (it is 92.16 ha at 900 m²/px) — corrected in the revision (R2 3, 3.2).
* Pixel area is assumed to be 900 m², but in EPSG:4326 it is 900 × cos(latitude) m². A "50 ha" patch therefore corresponds to ≈ 50 ha at the Equator and ≈ 43 ha at 30° S. Quantified in run **G3**.
* Forest pixels inside qualifying patches are retained (classes 3, 5, 6, 49); area is then computed with `ee.Image.pixelArea()` (true area).

### Habitat isolation — `03_fragmentation_isolation_stepD/E/F.js` (+ steps A–C, missing)
* Native-vegetation mask resampled to **100 m**; `connectedPixelCount` at 100 m (1 px = 1 ha), so source patches ≥ 1000 ha (1000 px) are identifiable below the 1024-pixel limit (R2 3.3).
* Sources: patches ≥ 100, 500 or 1000 ha. Targets: patches ≤ 25, 50 or 100 ha. Distance: Euclidean from source patches up to 25 km; target patch distance = minimum over the patch (`reduceConnectedComponents(min)`, 4-neighbour `connectedComponents`, `maxSize 550`).
* Classes: target patch ≥ 5, ≥ 10, ≥ 20 km from any source. Intermediate patches (between target and source size) are neither sources nor targets. Sources outside Brazil are not considered (border effect; discussed as a limitation).
* Final export at `scale: 30` (step F).

### Fire frequency — `07_fire_frequency.js`
* Annual burned-area maps binarized and summed from 1985 to year *t* → number of fires per pixel; only pixels that are forest in year *t* are kept. The metric is cumulative by construction (R2 3.4).

### Area tabulation — `getArea_IBGE.js` (and equivalent for biomes)
* `ee.Image.pixelArea().divide(1e4)` (ha), `reduceRegion(ee.Reducer.sum().group(1,'class').group(1,'territory'))`, `scale: 30`, `maxPixels: 1e12`, default projection of the input (EPSG:4326), no `bestEffort`, no `tileScale`.
* Forest mask of each year: classes 3, 5, 6, 49 → 1.
* Classes in the IBGE-type tables are **exclusive** bands (e.g. edge class 60 = 30–60 m); classes in the biome tables are **cumulative** (≤ d). Verified in R: exclusive classes sum to ≤ 100 % of forest.
