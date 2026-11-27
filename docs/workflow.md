# Methodological workflow (Reviewer 2, comment 4.1)

This flowchart is the source for the new Supplementary Figure S1 (methods flowchart). It renders on GitHub.

```mermaid
flowchart TD
  subgraph IN[Inputs]
    A1[MapBiomas LULC Collection 9<br/>annual, 1985-2023, 30 m, EPSG:4326]
    A2[MapBiomas Fire<br/>annual burned area - collection to confirm]
    A3[IBGE biomes 2019<br/>1:250,000]
    A4[IBGE potential vegetation map<br/>1:250,000]
  end

  subgraph PRE[Pre-processing in GEE, per year]
    B1[Native vegetation mask<br/>classes 3,4,5,6*,11,12,49,50<br/>Pantanal: + water 33 for patches/isolation]
    B2[Anthropogenic mask<br/>all other classes except 13,29,32,33]
    B3[Forest mask<br/>classes 3,5,6,49]
  end

  subgraph DRV[Driver rasters in GEE]
    C1[Edge area<br/>Euclidean distance to anthropogenic<br/>d = 30...1000 m, 30 m grid]
    C2[Small-sized patches<br/>connectedPixelCount 8-neighbour<br/>3...75 ha, 30 m grid]
    C3[Habitat isolation<br/>100 m grid, sources >=100/500/1000 ha<br/>targets <=25/50/100 ha<br/>col9: 5/10/20 km; col11: 0.1/0.2/0.5/1/5/10 km]
    C4[Fire frequency<br/>sum of annual burned maps 1985..t]
  end

  subgraph TAB[Area tabulation in GEE]
    D1[pixelArea in ha, reduceRegion sum<br/>grouped by class and territory<br/>scale 30, maxPixels 1e12]
  end

  subgraph R[R post-processing - this repository]
    E1[01 tidy exposure table<br/>% exposed = exposed / forest x 100]
    E2[02 Figure 1]
    E3[03 Mann-Kendall + Sen, rates]
    E4[04 PCA standardized, within-biome<br/>correlations raw and first differences]
    E5[05 threshold sensitivity]
    E6[06 denominator decomposition]
    E7[07 forest-type exposure ranking]
    E8[08 text consistency check]
  end

  A1 --> B1 & B2 & B3
  B1 --> C2 & C3
  B2 --> C1
  A2 --> C4
  B3 --> C1 & C2 & C3 & C4
  C1 & C2 & C3 & C4 --> D1
  A3 & A4 --> D1
  D1 --> E1 --> E2 & E3 & E4 & E5 & E6 & E7 & E8
```

`*` class 6 (floodable forest) is part of the native mask in the Amazon only, as coded.

Metrics recalculated **annually**: edge area, small-sized patches, habitat isolation (each year's
LULC map). **Cumulative**: fire frequency (fires from 1985 to year *t*, restricted to forest of year *t*).
