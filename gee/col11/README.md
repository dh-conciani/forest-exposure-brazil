# Collection 11: GEE steps for the paper

The MapBiomas Degradation Module tables `*-11.1a.xlsx` (edge area + edge age, patch size,
fire frequency, secondary vegetation; tables cover 1985–2025, the paper uses 1986–2024) are used
directly from `data/raw/col11/`. Habitat isolation is **not** in those tables and is produced by the
Colab pipeline in `isolation_pipeline/`.

## isolation_pipeline/

| File | What it is |
|---|---|
| `run_isolation_col11_colab.ipynb` | Colab notebook: authenticate → check inputs → test 2022 → run 1986–2024 in one call |
| `isolation_col11.py` | the pipeline (stage builders + self-managing scheduler); the notebook embeds the same file |
| `METHOD_CHANGES.md` | differences from the original v6/v7 JavaScript workflow |

Stages per year (all at 100 m, assets in
`projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/isolation/`):

```
S1 masks_100m_v1/masks_<y>        forest_bin, natural_bin, lulc
S2 conn_100m_v1/conn_<y>          connectedPixelCount (forest, natural)
S3 distance_100m_v1/distance_<y>  distance to sources >= 100/500/1000 px
S4 isolation_100m_v1/isolation_<y> 24 bands uso_t{T}_s{S}_d{D} (LULC class of isolated pixels)
S5 stats_v1/isolation_stats_<y>   forest area (30 m) by biome x class x combination  (+ CSV on Drive)
```

39 years × 6 exports = 234 tasks; the scheduler starts each one as soon as its inputs exist
(`max_concurrent = 1500`), retries failures twice, and can be re-run to resume.

After it finishes: download the Drive CSVs (`DEGRADATION-COL11-ISOLATION/isolation_forest_col11_<y>.csv`)
into `data/raw/col11/isolation/` and run `DEG_COLLECTION=col11 Rscript run_all.R`.

### Before running
1. Confirm the LULC Collection 11 asset id (`Config.lulc_asset`); `check_inputs()` fails if it is wrong.
2. Send the biome codes printed by `check_inputs()` to update `biome_code` in `R/utils.R`
   (and `Config.pantanal_code`, assumed 3).
