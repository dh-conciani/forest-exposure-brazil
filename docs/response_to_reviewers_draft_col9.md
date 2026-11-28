# Response to reviewers — DRAFT, Collection 9 version (superseded by response_to_reviewers_draft.md, Collection 11)

Manuscript PECON-D-26-00178 — "Tracking the decline: 40 years of forest degradation in Brazil"
Scope of this draft: only comments that required new analyses, new/revised figures or code
changes. Conceptual/wording comments (exposure vs. degradation, title, terminology) are answered
in the main response letter. Line numbers `[Lxxx]` to be filled after the text is revised.
Values below come from `outputs/tables/` (release `vX.Y.Z`); every number can be regenerated with
`Rscript run_all.R`. Items marked **[PENDING G#]** depend on new GEE exports (`docs/gee_new_runs.md`).

---

## General statement on reproducibility (Associate Editor; R2 2.1, 4.1)

> *R2 2.1: Reconcile the manuscript with the GitHub repository … Provide a frozen release or commit, preferably with a DOI … Clarify which operations were performed in GEE and R.*

We thank the reviewer for checking the code. The repository cited in the submitted version
(`mapbiomas/brazil-degradation`) is the operational code of the MapBiomas Degradation Module,
which was updated to Collection 10.1 and Fire Collection 4.1 after our analysis; the Collection 9
scripts used in the paper were kept only in its `old/` folder. To remove this ambiguity we created a
dedicated research compendium (`<repository URL>`, archived on Zenodo, DOI `10.5281/zenodo.XXXXXXX`)
that contains (i) the exact GEE scripts used for the paper (Collection 9), with their asset ids and
parameters; (ii) the raw area tables exported from GEE; and (iii) a single R pipeline
(`run_all.R`, package versions pinned with `renv`) that regenerates every table, statistic and
figure of the manuscript and Supplementary Material. The division of work is now explicit: all
raster operations (masks, distances, patch labelling, fire accumulation, area tabulation) were done
in GEE; R was used only for post-processing (proportions, statistics, figures). We also added a
methodological flowchart (new Fig. S1; R2 4.1) describing inputs and versions, class harmonization,
masks, projection, annual vs. cumulative processing, area tabulation and R steps, and we state in the
Methods which metrics were recalculated annually (edge area, small-sized patches, isolation) and which
are cumulative (fire frequency).

**Changes:** Methods [Lxxx], Code and data availability [Lxxx], new Fig. S1, Text S1.
**Code:** `gee/README.md`, `docs/workflow.md`, `run_all.R`.

---

## Google Earth Engine functions and parameterization (R2 3, 3.1–3.5)

> *R2 3 / 3.2: The manuscript incorrectly equates 1,024 pixels with 75 ha instead of 92.16 ha …*

The reviewer is correct, and we apologize for the error in the text; the code itself did not rely on
that equivalence. Patch-size thresholds were converted to pixel counts as
`n = ha × 10,000 / 900` and `connectedPixelCount()` was called with `maxSize = n + 5` and
8-neighbour connectivity; the largest threshold (75 ha = 833 pixels; `maxSize` = 838) is therefore
below the 1,024-pixel limit, and every patch ≤ 75 ha is labelled exactly. Patches were defined on the
dissolved native-vegetation mask (all native classes), and only the forest pixels inside qualifying
patches were counted, so the metric is "forest area located in native-vegetation patches ≤ X ha";
this distinction from forest-patch area is now explicit in the Methods. We also now report that the
MapBiomas grid is geographic (EPSG:4326, 0.00026949°), so the pixel-count conversion assumes 900 m²
per pixel whereas the true pixel area is ≈ 900 × cos(latitude) m²; areas reported in the paper were
always computed with `ee.Image.pixelArea()` (true area), but the *threshold* is slightly smaller in
true area at higher latitudes (≈ 43 ha instead of 50 ha at 30° S). **[PENDING G3]** We quantified the
effect of this approximation by recomputing the 2022 small-patch class with thresholds in true area:
`<result>`.

> *R2 3.1: Specify the distance algorithm …*

Edge distance was computed with `anthropogenicMask.distance(ee.Kernel.euclidean(d + 10, 'meters'))`
and forest pixels with distance < d were retained, for d = 30 … 1000 m, at the native 30-m grid;
distances are measured between pixel centres. As a result the ≤ 30 m class contains the forest
pixels sharing a side with an anthropogenic pixel (diagonal neighbours, ≈ 42 m, fall in the ≤ 60 m
class). These details, together with the classes that do not generate or receive edges, are now in
the Methods and Text S1. **[PENDING G3]** Recomputing 2022 edge area in an equal-area projection
(EPSG:5880) changed national edge exposure by `<x>` percentage points.

> *R2 3.3: Explain how source patches of at least 1,000 ha were identified despite the 1,024-pixel limit …*

The isolation workflow runs on a native-vegetation mask resampled to 100 m, where one pixel equals
1 ha; source patches (≥ 1,000 ha = 1,000 pixels) are therefore identified within the 1,024-pixel
limit. Distances are Euclidean from source patches (up to 25 km) and a target patch takes the
minimum distance of its pixels. Patches between the target and source sizes are neither sources nor
targets; sources outside Brazil are not considered (now listed as a limitation for border regions).
Because the GEE export contains all combinations of source size (≥ 100, 500, 1,000 ha) and target size
(≤ 25, 50, 100 ha), we now report all of them (new Table S6c). For example, Atlantic Forest exposure
at ≥ 5 km in 2022 ranges from 1.8 % (sources ≥ 100 ha, targets ≤ 25 ha) to 15.0 % (sources ≥ 1,000 ha,
targets ≤ 100 ha); the main text keeps the latter combination and states it explicitly.

*Collection 11 update.* In the revised analysis (MapBiomas Collection 11, 1986–2024) isolation was
recomputed with three changes that address R2 3.1–3.3 directly:
(i) patch sizes come from the Degradation Module patch-size product (8-neighbour clumps, true pixel
area in ha), so there is no 1,024-pixel limit and sources ≥ 1,000 ha are exact;
(ii) distances from source patches are computed in an equal-area metric projection (SIRGAS 2000 /
Brazil Polyconic, EPSG:5880) at 100 m, so a given threshold means the same distance at every latitude;
(iii) distance classes were widened to ≥ 0.5, 1, 2, 5 and 10 km, so the response of isolation to the
distance threshold is shown along the whole gradient (Fig. 1c, Table S6c). The main scenario remains
sources ≥ 1,000 ha, targets ≤ 100 ha, ≥ 5 km. The forest reference area used as denominator was
checked against the module tables (difference `<x>` %). **[PENDING: isolation CSVs from GEE]**
Atlantic Forest exposure at ≥ 5 km in 2024 is `<x>` % (Collection 9, 2022: 15.0 %); Table S10
compares both collections for every driver.

> *R2 3.4: Fire frequency …*

Fire frequency is the number of years a pixel burned between 1985 and year *t*, restricted to pixels
that are forest in year *t*; it is therefore cumulative and cannot decrease except through forest loss.
We now (i) state this explicitly, (ii) flag it in all trend tables, (iii) report PCA results with and
without fire (Table S5), and **[PENDING G2]** (iv) add the annual forest area burned in each year as a
non-cumulative series, used for trend tests and correlations (new Table Sx).

> *R2 3.5: Report ee.Image.pixelArea() processing parameters …*

Added to Text S1: `pixelArea()/1e4` (ha), `reduceRegion` with `Reducer.sum().group()` by class and
territory, `scale = 30`, `maxPixels = 1e12`, input projection (EPSG:4326), no `bestEffort` or
`tileScale`; biome limits rasterized from IBGE (2019, 1:250,000). Biome tables use cumulative
threshold classes (≤ d), whereas the vegetation-type tables use exclusive classes (e.g. 30–60 m);
both are documented and handled explicitly in the code.

---

## Data and accuracy (R2 2.3, 2.5, 5.4)

> *R2 2.3: Report forest-class accuracy by biome … sensitivity tests excluding very small patches.*

**[PENDING G4, G5]** We now report user's and producer's accuracy of the forest classes per biome
for Collection 9 (Table S2) and a sensitivity test excluding patches < 0.5 ha and < 1 ha
(`<result>`).

> *R2 5.4: Harmonize inconsistent patch-size limits (50, 75 and 100 ha) …*

The three numbers refer to different parameters, which we now separate clearly: small-sized patch
thresholds (≤ 3 … 75 ha; scenario ≤ 50 ha) and the maximum size of *target* patches in the isolation
analysis (≤ 100 ha; results for ≤ 25 and ≤ 50 ha in Table S6c).

---

## Variable selection, thresholds and denominator (R2 5.5, 5.7, 9.4)

> *R2 5.5: Assess how deforestation and regeneration alter the proportion of exposed forest independently of changes in exposure …*

We decomposed the change in the proportion of exposed forest (p = E/F) between 1986 and 2022 into
the change in exposed area (E) and in forest area (F): ln(p₂₀₂₂/p₁₉₈₆) = ln(E₂₀₂₂/E₁₉₈₆) − ln(F₂₀₂₂/F₁₉₈₆)
(new Table S7). Forest loss explains a small part of the increase in fire exposure (2–8 %) and of
isolation in the Amazon (4 %), but a substantial part of the increase in edge exposure in the Cerrado
(67 %) and Pantanal (66 %). In the Atlantic Forest and Caatinga the proportion of forest within
150 m of an edge increased only because forest area shrank: the absolute edge area decreased
(share from the denominator > 100 %). In the Pampa forest area increased (+8.9 %), so the observed
increase in exposure occurred despite a growing denominator. **[PENDING G1]** We complemented this
with the analysis restricted to a stable-forest mask (forest in all years 1986–2022): `<result>`.

> *R2 5.7: Correct the direction of isolation-threshold results and explicitly link each reported value to its threshold.*

Corrected. Every range in the text now states the thresholds that bound it (e.g. "4.9 % (≥ 20 km) to
15.0 % (≥ 5 km)"), and threshold-specific values are provided for all biomes, drivers and years in
Tables S3 and S6a. The literature-based scenario (≤ 150 m, ≤ 50 ha, ≥ 5 km, ≥ 1 fire) is used
consistently for all single-value comparisons.

> *R2 9.4: Evaluate how conclusions and biome rankings change across thresholds.*

We ranked biomes by exposure in 2022 for every threshold of every driver (new Fig. S3, Table S6a)
and measured the agreement among rankings with Kendall's coefficient of concordance (Table S6b).
Rankings were highly consistent across thresholds (W = 0.99 for edge area, 0.97 small-sized
patches, 0.95 isolation, 0.95 fire frequency). The Atlantic Forest (or the Pampa, for edge area)
was the most exposed biome under every fragmentation threshold, and the Pantanal or Cerrado under
every fire threshold; biome comparisons in the text are therefore robust to threshold choice.

---

## Statistical analyses (R2 6.1–6.5)

> *R2 6.1: Reassess the PCA by standardizing variables, centering within biomes, and removing Brazil …*

We agree. The submitted PCA used unstandardized proportions (`scale. = FALSE`) and included Brazil as
an additional observation; edge area, having the largest variance, therefore dominated PC1. The PCA
was redone (revised Fig. 3, Table S5) (a) on standardized variables using the six biomes only
(6 × 37 biome-years) and (b) on variables centered and scaled within each biome, which removes
between-biome differences and retains only joint temporal variation. In (a), PC1 (73.7 %) is
associated with the three fragmentation metrics (loadings 0.56–0.57) and separates the
historically fragmented biomes (Atlantic Forest, Pampa) from the others, while PC2 (23.3 %) is
associated almost exclusively with fire (loading −0.98) and separates Pantanal and Cerrado. In (b),
PC1 (84.9 %; 91.8 % without fire) reflects the shared increase of all metrics over time. We now
interpret explained variance as covariation among metrics, not as the contribution of each driver
to degradation, and we removed the statement that fragmentation "explained 92 %" of degradation.

> *R2 6.2: Clarify whether Pearson correlations were calculated from raw time series or first differences …*

They were calculated from raw series. We now report both (revised Fig. S2, Table S5c). Raw
correlations were high for almost all pairs (r > 0.8 in most biomes), but most of this reflected
shared trends: on first differences, the only consistent association was between small-sized
patches and isolation (r = 0.43–0.91, significant in five biomes), and edge area was associated with
small patches in the Amazon, Caatinga and Pantanal (r = 0.50–0.74). After differencing, fire was not
significantly correlated with any fragmentation metric, except a negative association with edge
area in the Atlantic Forest (r = −0.49). The text no longer interprets raw
correlations as evidence of coupled dynamics.

> *R2 6.3: Apply statistical trend tests … Report significant combinations and revise unsupported claims …*

We applied the Mann-Kendall test with Sen's slope to each biome × driver × threshold combination
(162 tests; Benjamini–Hochberg correction; Table S3). Exposure increased significantly in 140 of
them (all 60 fire tests, which are cumulative by construction; 80 of 102 fragmentation tests). Exceptions were concentrated in the Caatinga, where the proportion of forest near edges
(≤ 30–300 m) and in small-sized patches (all thresholds) decreased significantly (Sen's slope
−0.03 to −0.06 p.p./yr for edges), and in a few large-threshold classes in the Atlantic Forest and
Pampa (edge ≥ 600 m) with no significant trend. The claim that exposure "increased in all biomes"
was revised accordingly; fire frequency trends are reported but flagged as cumulative.

> *R2 6.4: Calculate absolute and relative annual rates … Cerrado experienced the fastest increase.*

Table S4 reports Sen's slopes in percentage points per year and in hectares per year under the
scenario thresholds. In relative terms the Cerrado had the fastest increase in edge exposure
(0.31 p.p./yr) and isolation (0.13 p.p./yr), the Pampa in small-sized patches (0.05 p.p./yr) and the
Pantanal in fire (0.73 p.p./yr, followed by the Cerrado, 0.54 p.p./yr). In absolute terms the Amazon
had the fastest increase for edge (2.7 × 10⁵ ha/yr), small patches and fire. The text now
distinguishes these two statements (also addressing R2 8.2).

> *R2 6.5 / 1.6: Define the ranking method …; rename the Red List.*

The ranking is now called an "exposure ranking of forest types" and its method is explicit:
reference year 2022, scenario thresholds, equal weights, ordering by the mean proportion of exposed
forest across the four drivers; the forest mask of each year (MapBiomas classes 3, 5, 6, 49, 30 m) was
intersected with the IBGE potential-vegetation map rasterized on the same grid. Sensitivity
(Table S8b): the same three types (SSF, MOF, DSF) occupied the top three positions, and ESF the fourth,
under every alternative tested — reference year 2010, removal of any single driver, and rank-sum
instead of mean-proportion aggregation; only the order within the top three changed (SSF first in
2022, MOF first in 2010 and in most leave-one-out runs). Vegetation types that are not forest physiognomies in the
IBGE map (savanna, steppe, campinarana, pioneer formations, ecological tension zones) were excluded
because they mix forest and non-forest; this is now justified in the text, and their values are
provided in Table S8a.

---

## Results and figures (R1 figure comments; R2 8.1–8.9)

> *R1: Figure 1 … use a sequential colour scale … also applies to Figure 2 and the Box figure.*

Done. Figure 1 and Figure 4 now use a sequential palette (ColorBrewer RdPu), with darker colours for
the most severe thresholds; Figure 2 maps were recoloured with the same scheme **[PENDING — QGIS]**.

> *R2 8.9: Eliminate overlapping edge-class intervals in Fig. 1a, remove Brazil from the PCA, improve year-label legibility in Fig. 3, correct the duplicated caption and colour range in Fig. 4.*

All done: Fig. 1 now shows cumulative thresholds (≤ 30 m … ≤ 1,000 m), avoiding the overlapping
"600–1000" interval; Brazil was removed from the PCA and year labels were replaced by a colour/alpha
gradient with trajectories (Fig. 3); Fig. 4 caption is no longer duplicated and the colour range is
fixed to 0–100 %.

> *R2 8.1: Reconcile "fire highly impactful" with 7 % of variation.*

With the standardized PCA, fire defines its own axis (PC2, 23.3 % of the variance) rather than a
residual one; nevertheless we now describe fire as a widespread and increasing *exposure*, not as
"highly impactful", following both reviewers.

> *R2 8.3: Atlantic Forest isolation 4.9–15 % vs Fig. 1c ~25 %.*

The values in the text are correct (4.9 % at ≥ 20 km to 15.0 % at ≥ 5 km in 2022; sources ≥ 1,000 ha,
targets ≤ 100 ha). The revised Fig. 1c is generated directly from the same table and matches the
text and Table S2.

> *R2 8.4: Quantify the description of the Atlantic Forest as relatively stable.*

Quantified: edge exposure (≤ 150 m) increased by 0.08 p.p./yr in the Atlantic Forest versus 0.31 in
the Cerrado and 0.26 in the Pampa, and showed no significant trend at ≥ 600 m; moreover, the absolute
edge area decreased and the small increase in proportion is attributable to forest loss (Table S7).

> *R2 8.6 / 1.7: 37 vs 40 years; report burned area and percentage for every biome.*

The period is now described as 37 years (1986–2022). A table with forest area burned at least once
(ha and %) for every biome was added. While recomputing these values we corrected three numbers in
the text: forest burned at least once by 2022 is 21.5 % in the Cerrado (not 19 %), 29.4 % in the
Pantanal (not 28 %) and 16.8 Mha in the Amazon (not 16.2 Mha) **[CONFIRM: earlier values may have
counted fires from 1986 rather than 1985]**.

> *R2 8.8: Protected forests (37 %).*

**[PENDING G6]** Method, sources (CNUC/MMA and FUNAI, reference dates) and results by biome added.

---

## Graphical abstract (R1; R2 10.1)

**[PENDING — design]** Replaced by a results-oriented graphic: 2022 combined-exposure map (number of
drivers per pixel under the scenario), 1986–2022 trends by driver and biome (from Fig. 1 data), and
the four indicators with their thresholds. Outward edge representation, core-forest element and the
fire ↔ fragmentation causal arrows were removed.
