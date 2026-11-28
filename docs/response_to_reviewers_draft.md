# Response to reviewers — DRAFT (Collection 11; items involving re-analysis, figures and reproducibility)

Manuscript PECON-D-26-00178 — "Tracking the decline: 40 years of forest degradation in Brazil"
Scope of this draft: comments that required new analyses, new/revised figures or code changes.
Conceptual/wording comments (exposure vs. degradation, title, terminology) are answered in the main
response letter. Line numbers `[Lxxx]` to be filled after the text is revised.
All values come from `outputs/col11/tables/` and are regenerated with
`DEG_COLLECTION=col11 Rscript run_all.R`; the Collection 9 values reviewed in the first round are in
`outputs/col9/` and compared in Table S10. The previous (Collection 9) version of this draft is
`docs/response_to_reviewers_draft_col9.md`.
Markers: **[ISOL]** = waits for the Collection 11 isolation tables (GEE export running);
**[PENDING G#]** = depends on an optional GEE run (`docs/gee_new_runs.md`).

---

## Opening statement for the letter — update to MapBiomas Collection 11

> *Proposed paragraph for the beginning of the response letter.*

In revising the manuscript we updated the whole analysis from MapBiomas Collection 9 (1986–2022) to
Collection 11 (1986–2024), the most recent release of the land-use and land-cover maps and of the
MapBiomas Degradation Module. We did so for three reasons. First, Collection 11 is the current
public version; keeping the paper on a superseded collection would make it inconsistent with the
maps, statistics and code that readers can download from the MapBiomas platform. Second, it keeps
the paper synchronized with the MapBiomas Degradation working group: edge area, small-sized patches
and fire frequency are now taken directly from the official Degradation Module statistics
(tables 11.1a), and isolation is computed from the module's own patch-size product, so every metric
in the paper uses the same inputs, definitions and code as the public module (R2 2.1). Third,
Collection 11 directly resolves several methodological points raised by Reviewer 2: patch sizes are
computed with 8-neighbour clumps in true pixel area, with no 1,024-pixel limit (R2 3.2, 3.3); the
series is two years longer (39 annual maps); and the module adds the age of each edge, which we now
report (new Fig. S4). The update changes some values, mainly because Collection 11 reclassified the
Cerradão as forest (Cerrado forest area +33 to +38 % relative to Collection 9) and because the
module's edge and fire products were revised. New Table S10 compares, for every driver and biome,
the values of the reviewed version (Collection 9) with the revised ones (Collection 11), so the
reviewers can see exactly what changed; the conclusions of the paper are unchanged
**[CONFIRM after ISOL]**.

---

## General statement on reproducibility (Associate Editor; R2 2.1, 4.1)

> *R2 2.1: Reconcile the manuscript with the GitHub repository … Provide a frozen release or commit, preferably with a DOI … Clarify which operations were performed in GEE and R.*

We thank the reviewer for checking the code. The discrepancy arose because the repository cited in
the submitted version (`mapbiomas/brazil-degradation`) is the operational code of the MapBiomas
Degradation Module, which had already moved to a newer collection while the paper used Collection 9.
We removed this mismatch in two ways. First, the revised analysis uses Collection 11, the same
collection as the current public module, so the paper and the operational code now describe the same
data. Second, we created a dedicated research compendium (`<repository URL>`, archived on Zenodo,
DOI `10.5281/zenodo.XXXXXXX`) that contains (i) the GEE scripts used for the paper, with asset ids and
parameters (including the isolation workflow, run in three steps: 100 m distances, 30 m maps and area
tables); (ii) the raw area tables; and (iii) a single R pipeline (`run_all.R`, package versions pinned
with `renv`) that regenerates every table, statistic and figure of the manuscript and Supplementary
Material, for Collection 11 and, for transparency, for the Collection 9 data of the reviewed version.
All raster operations (masks, patch sizes, distances, fire accumulation, area tabulation) were done
in GEE; R was used only for post-processing (proportions, statistics, figures). A methodological
flowchart (new Fig. S1; R2 4.1) describes inputs and versions, class harmonization, masks,
projections, annual vs. cumulative processing, area tabulation and the R steps; the Methods state
which metrics are recalculated annually (edge area, small-sized patches, isolation) and which is
cumulative (fire frequency).

**Changes:** Methods [Lxxx], Code and data availability [Lxxx], new Fig. S1, Text S1, Table S10.
**Code:** `gee/`, `docs/workflow.md`, `run_all.R`.

---

## Google Earth Engine functions and parameterization (R2 3, 3.1–3.5)

> *R2 3 / 3.2: The manuscript incorrectly equates 1,024 pixels with 75 ha instead of 92.16 ha …*

The reviewer is correct, and we apologize for the error in the text. In the reviewed version the code
did not rely on that equivalence (thresholds were converted with `n = ha × 10,000 / 900` and
`connectedPixelCount()` used `maxSize = n + 5`, so every patch ≤ 75 ha was labelled exactly). In the
revised analysis the question no longer arises: patch sizes come from the Collection 11 Degradation
Module, which labels native-vegetation patches with 8-neighbour connectivity and sums the true area
of their pixels (ha), with no pixel limit. Small-sized patch thresholds are now 5, 10, 25, 50 and
100 ha (scenario ≤ 50 ha). The metric is the forest area located in native-vegetation patches ≤ X ha,
not the area of forest-only patches; this is now explicit in the Methods. Areas are always computed
with `ee.Image.pixelArea()` (true area), so the geographic grid (EPSG:4326) does not bias the results.

> *R2 3.1: Specify the distance algorithm …*

Edge area comes from the Degradation Module, which measures the Euclidean distance from
anthropogenic land use and retains forest pixels within each distance class (30 … 1,000 m used here),
at the native 30-m grid, distances measured between pixel centres; the module also records the age of
each edge (years since the adjacent area was converted), reported in new Fig. S4 and Table S9: 81.7 %
of the forest within 150 m of an edge in 2024 bordered edges older than 20 years. For isolation,
distances are computed in an equal-area metric projection (SIRGAS 2000 / Brazil Polyconic,
EPSG:5880) at 100 m, so a given threshold means the same distance at every latitude. These details,
together with the classes that generate and receive edges, are in the Methods and Text S1.

> *R2 3.3: Explain how source patches of at least 1,000 ha were identified despite the 1,024-pixel limit …*

In the revised workflow, source and target patches are taken from the Degradation Module patch-size
product (true area, 8-neighbour, no pixel limit), so sources ≥ 1,000 ha are identified exactly. A
forest pixel is considered isolated when it lies in a native-vegetation target patch (≤ 25, 50 or
100 ha) whose minimum distance to a source patch (≥ 100, 500 or 1,000 ha) is ≥ 0.5, 1, 2, 5 or 10 km;
distances are computed at 100 m in EPSG:5880 and a target patch takes the minimum distance of its
cells. Patches between the target and source sizes are neither sources nor targets, and sources
outside Brazil are not considered (now a stated limitation for border regions). Sources and targets
are native-vegetation patches (all native classes), as in the reviewed version, and only forest
pixels are counted **[CONFIRM D2]**. All 45 combinations of source size, target size and distance are
reported (Table S6c); the main scenario is sources ≥ 1,000 ha, targets ≤ 100 ha, ≥ 5 km. The forest
area used as denominator was checked against the module tables (difference `<x>` %) **[ISOL]**.
Atlantic Forest exposure at ≥ 5 km was `<x>` % in 2024 (`<x>`–`<x>` % across source/target sizes)
**[ISOL]**.

> *R2 3.4: Fire frequency …*

Fire frequency is the number of years a pixel burned between 1985 and year *t*, restricted to pixels
that are forest in year *t*; it is therefore cumulative and cannot decrease except through forest
loss. We now (i) state this explicitly, (ii) flag it in all trend tables, (iii) report PCA results
with and without fire (Table S5), and **[PENDING G2]** (iv) add the annual forest area burned in each
year as a non-cumulative series, used for trend tests and correlations (new Table Sx).

> *R2 3.5: Report ee.Image.pixelArea() processing parameters …*

Added to Text S1: `pixelArea()/1e4` (ha), `reduceRegion` with `Reducer.sum()` grouped by class and
territory, `scale = 30`, `maxPixels = 1e13`, `tileScale = 4` (isolation tables), input projection
EPSG:4326 (EPSG:5880 for isolation distances at 100 m); biome limits rasterized from IBGE (2019,
1:250,000). Threshold classes are cumulative (≤ d for edges and patches, ≥ d for isolation and fire)
and this is stated in every figure and table.

---

## Data and accuracy (R2 2.3, 2.5, 5.4)

> *R2 2.3: Report forest-class accuracy by biome … sensitivity tests excluding very small patches.*

**[PENDING G4, G5]** We now report user's and producer's accuracy of the forest classes per biome
for Collection 11 (Table S2) and a sensitivity test excluding patches < 0.5 ha and < 1 ha
(`<result>`).

> *R2 5.4: Harmonize inconsistent patch-size limits (50, 75 and 100 ha) …*

The numbers referred to different parameters, which we now separate clearly and harmonize: small-
sized patch thresholds are 5–100 ha (scenario ≤ 50 ha), and the maximum size of *target* patches in
the isolation analysis is ≤ 25, 50 or 100 ha (scenario ≤ 100 ha), so both metrics now share the same
upper limit of 100 ha.

---

## Variable selection, thresholds and denominator (R2 5.5, 5.7, 9.4)

> *R2 5.5: Assess how deforestation and regeneration alter the proportion of exposed forest independently of changes in exposure …*

We decomposed the change in the proportion of exposed forest (p = E/F) between 1986 and 2024 into the
change in exposed area (E) and in forest area (F): ln(p₂₀₂₄/p₁₉₈₆) = ln(E₂₀₂₄/E₁₉₈₆) − ln(F₂₀₂₄/F₁₉₈₆)
(new Table S7). Forest area decreased by 14.0 % in Brazil, 22.3 % in the Cerrado and 21.9 % in the
Pantanal, and increased by 13.8 % in the Pampa. Forest loss explains a small part of the increase in
fire exposure (2–11 %) and of edge exposure in the Amazon (15 %), but a substantial part of the
increase in edge exposure in the Cerrado (46 %). In the Atlantic Forest the proportion of forest
within 150 m of an edge increased only because forest area shrank: the absolute edge area decreased
slightly (share from the denominator 128 %). In the Pampa, exposure increased despite a growing
denominator. **[ISOL]** isolation values to be added. **[PENDING G1]** We complemented this with an
analysis restricted to a stable-forest mask (forest in all years 1986–2024): `<result>`.

> *R2 5.7: Correct the direction of isolation-threshold results and explicitly link each reported value to its threshold.*

Corrected. Every range in the text now states the thresholds that bound it (e.g. "`<x>` % (≥ 10 km)
to `<x>` % (≥ 0.5 km)" **[ISOL]**), and threshold-specific values are provided for all biomes,
drivers and years in Tables S3 and S6a. The literature-based scenario (≤ 150 m, ≤ 50 ha, ≥ 5 km,
≥ 1 fire) is used consistently for all single-value comparisons.

> *R2 9.4: Evaluate how conclusions and biome rankings change across thresholds.*

We ranked biomes by exposure in 2024 for every threshold of every driver (new Fig. S3, Table S6a) and
measured the agreement among rankings with Kendall's coefficient of concordance (Table S6b).
Rankings were highly consistent across thresholds (W = 1.00 for edge area and small-sized patches,
0.97 for fire frequency, `<x>` for isolation **[ISOL]**). The Atlantic Forest was the most exposed
biome under every edge and small-patch threshold, and the Cerrado or Pantanal under every fire
threshold; biome comparisons in the text are therefore robust to threshold choice.

---

## Statistical analyses (R2 6.1–6.5)

> *R2 6.1: Reassess the PCA by standardizing variables, centering within biomes, and removing Brazil …*

We agree. The submitted PCA used unstandardized proportions and included Brazil as an additional
observation, so edge area, with the largest variance, dominated PC1. The PCA was redone (revised
Fig. 3, Table S5) (a) on standardized variables using the six biomes only (6 × 39 biome-years) and
(b) on variables centered and scaled within each biome, which removes between-biome differences and
keeps only joint temporal variation. In (a), PC1 (67.8 %) is associated with the fragmentation
metrics (loadings 0.68) and separates the historically fragmented biomes (Atlantic Forest, Pampa)
from the others, while PC2 (30.3 %) is associated almost exclusively with fire (loading −0.96) and
separates the Pantanal and Cerrado. In (b), PC1 (96.1 %; 98.1 % without fire) reflects the shared
increase of all metrics over time. **[ISOL]** values will change slightly when isolation is added.
We now interpret explained variance as covariation among metrics, not as the contribution of each
driver to degradation, and we removed the statement that fragmentation "explained 92 %" of
degradation.

> *R2 6.2: Clarify whether Pearson correlations were calculated from raw time series or first differences …*

They were calculated from raw series. We now report both (revised Fig. S2, Table S5c). Raw
correlations were high for every pair (r = 0.81–1.00), but this mostly reflected shared trends. On
first differences, edge area and small-sized patches remained associated in five biomes (r = 0.44–0.70,
significant after BH correction in the Amazon, Caatinga, Atlantic Forest, Pampa and Pantanal), whereas
fire was not significantly correlated with any fragmentation metric in any biome. **[ISOL]**
isolation pairs to be added. The text no longer interprets raw correlations as evidence of coupled
dynamics.

> *R2 6.3: Apply statistical trend tests … Report significant combinations and revise unsupported claims …*

We applied the Mann-Kendall test with Sen's slope to each biome × driver × threshold combination
(Benjamini–Hochberg correction; Table S3). Exposure increased significantly in 136 of the 138
combinations of edge area, small-sized patches and fire frequency (all 60 fire tests, which are
cumulative by construction; 76 of 78 fragmentation tests); the exceptions were the widest edge
classes in the Atlantic Forest (≤ 600 m, no significant trend; ≤ 1,000 m, significant decrease).
**[ISOL]** isolation tests to be added. The statement that exposure "increased in all biomes" is now
qualified accordingly, and fire trends are reported but flagged as cumulative.

> *R2 6.4: Calculate absolute and relative annual rates … Cerrado experienced the fastest increase.*

Table S4 reports Sen's slopes in percentage points per year and in hectares per year under the
scenario thresholds. In relative terms the Cerrado had the fastest increase in edge exposure
(0.45 p.p./yr) and small-sized patches (0.10 p.p./yr), and the Pantanal in fire (0.71 p.p./yr,
followed by the Cerrado, 0.64 p.p./yr). In absolute terms the Amazon had the fastest increase for
edge area (2.8 × 10⁵ ha/yr), small-sized patches (4.9 × 10⁴ ha/yr) and fire (4.0 × 10⁵ ha/yr).
**[ISOL]** isolation rates to be added. The text now distinguishes these two statements (also
addressing R2 8.2).

> *R2 6.5 / 1.6: Define the ranking method …; rename the Red List.*

The ranking is now called an "exposure ranking of forest types" and its method is explicit:
reference year, scenario thresholds, equal weights, ordering by the mean proportion of exposed forest
across the four drivers; the forest mask was intersected with the IBGE potential-vegetation map
rasterized on the same grid. Sensitivity (Table S8b): the same three types (SSF, MOF, DSF) occupied
the top three positions under every alternative tested (alternative reference year, removal of any
single driver, rank-sum aggregation). Vegetation types that are not forest physiognomies in the IBGE
map were excluded because they mix forest and non-forest; their values are provided in Table S8a.
**[DECIDE D4]** These results are from Collection 9, because the Collection 11 module tables by IBGE
vegetation type are not yet available; either request them or state this in the caption.

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

With the standardized PCA, fire defines its own axis (PC2, 30.3 % of the variance) rather than a
residual one; nevertheless we now describe fire as a widespread and increasing *exposure*, not as
"highly impactful", following both reviewers.

> *R2 8.3: Atlantic Forest isolation 4.9–15 % vs Fig. 1c ~25 %.*

The values in the reviewed text were correct for Collection 9 (4.9 % at ≥ 20 km to 15.0 % at ≥ 5 km in
2022); the figure used a different y-scale. In the revised version Fig. 1c and the text are generated
from the same Collection 11 table: Atlantic Forest isolation in 2024 ranges from `<x>` % (≥ 10 km) to
`<x>` % (≥ 0.5 km) **[ISOL]**.

> *R2 8.4: Quantify the description of the Atlantic Forest as relatively stable.*

Quantified: edge exposure (≤ 150 m) increased by 0.08 p.p./yr in the Atlantic Forest versus 0.45 in
the Cerrado and 0.32 in the Pampa, and decreased or showed no trend at the widest classes
(≤ 600–1,000 m); moreover, the absolute edge area decreased and the small increase in proportion is
attributable to forest loss (Table S7).

> *R2 8.6 / 1.7: 37 vs 40 years; report burned area and percentage for every biome.*

The period is now described as 39 years (1986–2024). A table with forest area burned at least once
since 1985 (ha and %) for every biome was added. In 2024 it was 27.2 % in the Cerrado (10.4 Mha),
33.5 % in the Pantanal (0.68 Mha), 6.3 % in the Amazon (20.6 Mha), 5.9 % in the Caatinga, 2.8 % in
the Atlantic Forest and 1.6 % in the Pampa (Brazil: 8.2 %, 32.8 Mha).

> *R2 8.8: Protected forests (37 %).*

**[PENDING G6]** Method, sources (CNUC/MMA and FUNAI, reference dates) and results by biome added.

---

## Graphical abstract (R1; R2 10.1)

**[PENDING — design]** Replaced by a results-oriented graphic: 2024 combined-exposure map (number of
drivers per pixel under the scenario), 1986–2024 trends by driver and biome (from Fig. 1 data), and
the four indicators with their thresholds. Outward edge representation, core-forest element and the
fire ↔ fragmentation causal arrows were removed.
