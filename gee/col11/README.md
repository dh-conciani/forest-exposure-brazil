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

## Alternativa em JS (Code Editor): `isolation_forest_col11.js`

Usa o tamanho de fragmento do próprio módulo de degradação
(`DEGRADATION/COLLECTION-11/area`, ImageCollection com uma imagem por ano,
`degradation_patch_size_col11_<ano>_v1`, 1 banda em ha) em vez de
`connectedPixelCount`. `CONFIG.distances` aceita N limiares (classes exclusivas). Exporta por ano um CSV
de áreas para o Drive e um mapa de 30 m (9 bandas `s<S>_t<T>`, uint8, valor = índice
da classe de distância, legenda na propriedade `values`) para a ImageCollection
`DEGRADATION/COLLECTION-11/isolation/forest_isolation`. O pipeline Python/Colab não
depende do asset de patch size e usa 5/10/20 km.

Limiares adotados no Col. 11 (decisão dos autores, 27/11/2026):
`[100, 200, 500, 1000, 5000, 10000]` m. O R (`isolation_from_js_long` em
`R/utils.R`) converte as classes exclusivas em exposição cumulativa (≥ d), com
`threshold` em km; o cenário principal continua ≥ 5 km.
