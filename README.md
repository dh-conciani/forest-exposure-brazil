# Forest exposure to degradation drivers in Brazil (1986–2022) — analysis compendium

Code and data to reproduce the tables, statistics and figures of

> Conciani et al. *Tracking the decline: forest exposure to degradation drivers in Brazil, 1986–2022.*
> Perspectives in Ecology and Conservation (revised submission, PECON-D-26-00178).

The repository is frozen at the release cited in the paper (`vX.Y.Z`, DOI: `10.5281/zenodo.XXXXXXX` — **to be minted on Zenodo after the final run**).
It documents *exactly* what was run for the paper. The operational MapBiomas
Degradation Module (<https://github.com/mapbiomas/brazil-degradation>) has since moved to
Collection 10.1 / Fire Collection 4.1 and other parameters; see [`gee/README.md`](gee/README.md)
for the mapping between the two.

## What is measured

The study quantifies **forest exposure to four degradation drivers** — not degradation itself
(no biomass, structure or biodiversity data are used). For each biome and year (1986–2022) we
compute the % of forest area that is:

| Driver | Operational definition | Thresholds (cumulative) | Scenario used in PCA / ranking |
|---|---|---|---|
| Edge area | forest pixel within *d* m of an anthropogenic pixel (`distance()` with `ee.Kernel.euclidean(d + 10 m)`, 30 m grid; see gee/README.md for the exact rule) | ≤ 30, 60, 90, 120, 150, 300, 600, 1000 m | ≤ 150 m |
| Small-sized patches | forest pixel inside a native-vegetation patch (8-neighbour) of area ≤ *a* ha | ≤ 3, 5, 10, 25, 50, 75 ha | ≤ 50 ha |
| Habitat isolation | forest pixel in a target native-vegetation patch ≤ 100 ha located ≥ *k* km from a source patch ≥ 1000 ha (100 m grid) | ≥ 5, 10, 20 km | ≥ 5 km |
| Fire frequency | forest pixel burned ≥ *n* times since 1985 (cumulative) | ≥ 1 … 10 fires | ≥ 1 fire |

Forest = MapBiomas Collection 9 classes 3 (Forest Formation), 5 (Mangrove), 6 (Floodable Forest) and
49 (Wooded Sandbank Vegetation) of the same year. Denominator = forest area of the biome in that year
(see `scripts/06_denominator_decomposition.R` for the effect of a changing denominator).

## Workflow

```
Google Earth Engine (JavaScript, gee/)                     R (this repository)
───────────────────────────────────────                    ─────────────────────────────────────────
MapBiomas LULC Col. 9 + Fire Col. 3   ──► driver rasters ──► area tables (CSV) ──► data/raw/
                                                                                     │
                                                         scripts/01_prepare_exposure.R
                                                                                     │
                                         data/derived/exposure_biome.csv (tidy, all thresholds)
                                                                                     │
          ┌───────────────┬──────────────────┬──────────────────┬─────────────────┬───┴────────────┐
       02 Fig. 1     03 trends/rates     04 PCA + corr.     05 threshold      06 denominator   07 forest-type
                     (Tables S3–S4)      (Fig. 3, S2, S5)   sensitivity (S6)  (Table S7)       ranking (Fig. 4, S8)
                                                                                     │
                                         08 numbers quoted in the text vs. recomputed values
```

A detailed flowchart with inputs, versions, masks, projections and parameters is in
[`docs/workflow.md`](docs/workflow.md).

## Data collections

The pipeline runs on two data versions, kept side by side (`data/derived/<collection>/`, `outputs/<collection>/`):

| `DEG_COLLECTION` | Source | Period | Notes |
|---|---|---|---|
| `col9` (default) | GEE exports used in the submitted manuscript (LULC Col. 9) | 1986–2022 | reproduces the submitted numbers |
| `col11` | MapBiomas Degradation Module tables `11.1a` (`data/raw/col11/*.xlsx`) | 1986–2024 (39 annual maps) | patch size in true area (GRASS); edge age available; isolation from `gee/col11/isolation_forest_col11.js` |

```bash
DEG_COLLECTION=col9  Rscript run_all.R
DEG_COLLECTION=col11 Rscript run_all.R   # then 10_compare_collections.R writes outputs/comparison/
```

In Collection 11 the small-patch thresholds are ≤ 5, 10, 25, 50, 100 ha (aligned with the ≤ 100 ha
isolation targets) and edge distances 30–1000 m are used (tables also hold 2.5 and 5 km).

## Reproduce

Requirements: R ≥ 4.3 (tested with 4.3.3 on Ubuntu 24.04 and on Windows 11). No GIS software is
needed for the R part; GEE steps require a Google Earth Engine account.

```r
# from the repository root (open forest-exposure-brazil.Rproj in RStudio, or setwd())
install.packages("renv")
renv::restore()          # installs the exact package versions in renv.lock
source("run_all.R")      # ~20 s; writes data/derived/<collection>/ and outputs/<collection>/
```

or from a terminal: `Rscript run_all.R`.

Every script runs in a clean environment and reads its inputs from disk; no script depends on
objects left in memory by another one.

## Repository layout

```
forest-exposure-brazil/
├── README.md               this file
├── DESCRIPTION             R dependencies (used by renv)
├── renv.lock               exact package versions
├── run_all.R               runs the whole R pipeline
├── R/utils.R               configuration (period, forest classes, scenario) + helper functions
├── scripts/                numbered analysis scripts (01–08), one output family each
├── data/
│   ├── raw/biome/          GEE exports by biome (MapBiomas statistics, Col. 9 — "9.0.1a")
│   ├── raw/ibge_vegetation/ GEE exports by IBGE vegetation type + id lookup
│   ├── raw/col11/          Degradation Module tables 11.1a (xlsx) + isolation/ (from GEE)
│   └── derived/<collection>/ tidy tables produced by 01_prepare_exposure.R
├── outputs/
│   ├── <collection>/figures/ Fig. 1, 3, 4 and supplementary figures (PNG 600 dpi + PDF)
│   ├── <collection>/tables/  supplementary tables and the text-consistency check
│   └── comparison/          Collection 9 vs 11 (Table S10)
├── gee/
│   ├── README.md           GEE scripts used, asset ids, parameters, provenance
│   ├── submitted_col9/     JavaScript versions used for the submitted analysis
│   └── col11/              Colab isolation pipeline for Collection 11 (+ README)
└── docs/
    ├── workflow.md          methodological flowchart (R2 comment 4.1)
    ├── gee_new_runs.md      new GEE exports needed for the revision
    ├── revision_tracker.csv comment → action → script/figure → status
    └── response_to_reviewers_draft.md
```

## Outputs ↔ manuscript

| Output | Manuscript item | Script |
|---|---|---|
| `fig1_exposure_timeseries` | Figure 1 | 02 |
| `tableS3_trends_mannkendall_sen`, `tableS3b_trend_counts` | Table S3 (new) | 03 |
| `tableS4_rates_scenario` | Table S4 (new) | 03 |
| `fig3_pca_revised`, `tableS5a/b` | Figure 3, Table S5 | 04 |
| `figS2_correlations_raw_vs_diff`, `tableS5c` | Figure S2 | 04 |
| `figS3_rank_sensitivity`, `tableS6a–c` | Figure S3, Table S6 (new) | 05 |
| `tableS7_denominator_decomposition` | Table S7 (new) | 06 |
| `fig4_forest_type_exposure_ranking`, `tableS8a/b` | Box 1 / Figure 4, Table S8 | 07 |
| `text_numbers_check` | internal QA of values quoted in the text (col9) | 08 |
| `figS4_edge_age`, `tableS9_edge_age_150m` | Figure S4, Table S9 (col11) | 09 |
| `comparison/tableS10_col9_vs_col11_scenario` | Table S10 | 10 |

Figure 2 (maps) is produced from the GEE rasters in QGIS; see `gee/README.md`.

## Why R + renv (and not a WSL/Ubuntu stack)

All post-processing is already in R and needs no system libraries (no GDAL/GRASS): the heavy
raster work happens in GEE. `renv` pins package versions and works identically on Windows,
macOS and Linux, so co-authors and reviewers can reproduce the results without WSL. WSL/Docker
would only be justified if the GRASS-based patch workflow of the current MapBiomas module were
brought into this paper, which it is not.

## Data availability

Maps and statistics: MapBiomas Degradation Module (<https://plataforma.brasil.mapbiomas.org/>).
Inputs in `data/raw/` are the exact CSV exports used in the paper.

## License

Code: MIT. Data: CC-BY 4.0 (MapBiomas).
