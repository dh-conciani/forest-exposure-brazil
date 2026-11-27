"""
isolation_col11.py
==================

Habitat-isolation pipeline (MapBiomas Degradation Module, ATBD v2 section 2.6)
ported from the original GEE JavaScript workflow (v6/v7, Collection 8) to Python,
updated to MapBiomas LULC **Collection 11**, years **1986-2024**, and wrapped in a
self-managing task scheduler: one call to ``run_pipeline()`` builds every stage,
starts each export as soon as its inputs exist, monitors all tasks, retries
failures and can be resumed after a disconnection.

Stages (one asset per year per stage; all at 100 m)
---------------------------------------------------
S1  masks      forest_bin, natural_bin, lulc               (original step A)
S2  conn       conect_forest, conect_natural               (original step B)
               connectedPixelCount(1024, 8-neighbour)
S3  distance   dist_s100, dist_s500, dist_s1000            (original step C)
               Euclidean distance (25 km kernel) to source patches
               (natural patches >= 100/500/1000 px); 25001 where no source
S4  isolation  uso_t{T}_s{S}_d{D}  (24 bands)              (original steps D + E)
               target patches <= 25/50/100 px (4-neighbour components), minimum
               distance per target patch > 5/10/20 km, value = LULC class
S5  stats      area (ha, 30 m) of FOREST in isolated targets, by biome x LULC
               class, for the 24 combinations + forest reference  (new: feeds R)

Method differences with respect to the original code are listed in
METHOD_CHANGES.md and flagged in the code with ``# CHANGE:``.

Usage (Colab)
-------------
    import ee, isolation_col11 as iso
    ee.Authenticate(); ee.Initialize(project="mapbiomas-brazil")
    cfg = iso.Config()                 # edit fields if needed
    iso.check_inputs(cfg)              # fails fast if an asset id is wrong
    iso.run_pipeline(cfg, years=[2022])   # test year
    iso.run_pipeline(cfg)                 # all years, single run
"""

from __future__ import annotations

import dataclasses
import json
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Dict, List, Optional

import ee

# =============================================================================
# Configuration
# =============================================================================


@dataclass
class Config:
    # ---- inputs --------------------------------------------------------------
    # TODO (verify): MapBiomas LULC Collection 11 integration asset,
    # bands "classification_<year>". The checker below fails if it does not exist.
    lulc_asset: str = (
        "projects/mapbiomas-public/assets/brazil/lulc/collection11/"
        "mapbiomas_brazil_collection11_coverage_v1"
    )
    biomes_asset: str = "projects/mapbiomas-workspace/AUXILIAR/biomas-raster-41"
    pantanal_code: int = 3  # value of Pantanal in biomes_asset (module script 05a uses eq(3))

    # ---- outputs -------------------------------------------------------------
    root: str = "projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/isolation"
    version: str = "1"
    stats_to_drive: bool = True          # also write the S5 tables to Google Drive
    drive_folder: str = "DEGRADATION-COL11-ISOLATION"

    # ---- period ----------------------------------------------------------------
    years: List[int] = field(default_factory=lambda: list(range(1986, 2025)))

    # ---- class definitions (original step A, Collection 8 legend = Collection 11 codes)
    # "forest" mask of the original code (NB: it also contains 11, 12, 50 - kept as is)
    forest_bin_classes: List[int] = field(default_factory=lambda: [3, 4, 5, 6, 11, 12, 49, 50])
    # natural mask of the original code, without water (33); water handled below
    natural_classes: List[int] = field(
        default_factory=lambda: [3, 4, 5, 6, 49, 11, 12, 13, 29, 32, 50, 23])
    # CHANGE: water (33) as natural only in the Pantanal (ATBD v2 / module script 05a).
    # The original v6 code used water as natural in every biome -> "all".
    water_as_natural: str = "pantanal"   # "pantanal" | "all" | "none"
    # classes written in the S4 "uso" bands (original step E: forest + non-forest classes)
    uso_classes: List[int] = field(default_factory=lambda: [3, 4, 5, 6, 49, 11, 12, 32, 29, 50])
    # forest definition of the paper (S5 statistics)
    paper_forest_classes: List[int] = field(default_factory=lambda: [3, 5, 6, 49])

    # ---- isolation parameters ------------------------------------------------------
    source_sizes: List[int] = field(default_factory=lambda: [100, 500, 1000])  # px >= (~ha)
    target_sizes: List[int] = field(default_factory=lambda: [25, 50, 100])     # px <= (~ha)
    distances_m: List[int] = field(default_factory=lambda: [5000, 10000, 20000])
    skip_source_le_target: bool = True   # original: target 100 x source 100 not computed
    max_distance_m: int = 25000          # distance kernel radius; beyond -> no_source_value
    no_source_value: int = 25001

    # ---- processing --------------------------------------------------------------
    scale: int = 100
    crs: str = "EPSG:4326"               # original: reproject('epsg:4326', null, 100)
    # target components: original uses ee.Kernel.plus(1) (4-neighbour)
    target_connectedness: str = "plus"   # "plus" (original) | "square" (8-neighbour)
    stats_scale: int = 30
    region_bbox: List[float] = field(default_factory=lambda: [-74.1, -34.0, -28.6, 5.4])

    # ---- scheduler ---------------------------------------------------------------
    max_concurrent: int = 1500
    poll_seconds: int = 60
    max_retries: int = 2
    overwrite: bool = False              # False -> existing assets are kept (resume)
    log_file: str = "isolation_col11_log.jsonl"

    # derived -------------------------------------------------------------------
    def coll(self, name: str) -> str:
        return f"{self.root}/{name}_100m_v{self.version}"

    @property
    def stats_folder(self) -> str:
        return f"{self.root}/stats_v{self.version}"

    def combos(self):
        """(target, source, distance) combinations, in a stable order."""
        out = []
        for t in self.target_sizes:
            for s in self.source_sizes:
                if self.skip_source_le_target and s <= t:
                    continue
                for d in self.distances_m:
                    out.append((t, s, d))
        return out


def band_name(t: int, s: int, d: int) -> str:
    return f"uso_t{t}_s{s}_d{d // 1000}"


# =============================================================================
# Helpers
# =============================================================================


def _region(cfg: Config) -> ee.Geometry:
    return ee.Geometry.Rectangle(cfg.region_bbox, "EPSG:4326", False)


def asset_exists(asset_id: str) -> bool:
    try:
        ee.data.getAsset(asset_id)
        return True
    except ee.EEException:
        return False


def ensure_container(asset_id: str, kind: str) -> None:
    """Create a FOLDER or IMAGE_COLLECTION (and missing parents) if needed."""
    if asset_exists(asset_id):
        return
    parent = asset_id.rsplit("/", 1)[0]
    if parent.count("/") >= 3 and not asset_exists(parent):
        ensure_container(parent, "FOLDER")
    ee.data.createAsset({"type": kind}, asset_id)
    print(f"created {kind}: {asset_id}")


def check_inputs(cfg: Config) -> None:
    """Fail fast with a clear message if an input asset or band is missing."""
    for a in (cfg.lulc_asset, cfg.biomes_asset):
        if not asset_exists(a):
            raise ValueError(f"Input asset not found or no access: {a}")
    bands = ee.Image(cfg.lulc_asset).bandNames().getInfo()
    missing = [y for y in cfg.years if f"classification_{y}" not in bands]
    if missing:
        raise ValueError(f"LULC asset lacks bands for years: {missing}")
    codes = ee.Image(cfg.biomes_asset).reduceRegion(
        ee.Reducer.frequencyHistogram(), _region(cfg), 5000, maxPixels=1e9).getInfo()
    print("Inputs OK. Biome codes found:", codes)


# =============================================================================
# Stage builders (pure ee graphs; nothing is computed until export)
# =============================================================================


def build_s1_masks(cfg: Config, year: int) -> ee.Image:
    lulc = ee.Image(cfg.lulc_asset).select(f"classification_{year}")
    forest_bin = lulc.remap(cfg.forest_bin_classes, [1] * len(cfg.forest_bin_classes), 0)
    natural = lulc.remap(cfg.natural_classes, [1] * len(cfg.natural_classes), 0)
    water = lulc.eq(33)
    if cfg.water_as_natural == "all":
        natural = natural.Or(water)
    elif cfg.water_as_natural == "pantanal":
        pantanal = ee.Image(cfg.biomes_asset).eq(cfg.pantanal_code).unmask(0)
        natural = natural.Or(water.And(pantanal))
    img = ee.Image.cat([forest_bin.rename("forest_bin"), natural.rename("natural_bin"),
                        lulc.rename("lulc")])
    return img.toByte().set({"year": year, "stage": "masks"})


def build_s2_conn(cfg: Config, year: int) -> ee.Image:
    m = ee.Image(f"{cfg.coll('masks')}/masks_{year}")

    def con(b):
        return (m.select(b).selfMask().connectedPixelCount(1024, True)
                .reproject(cfg.crs, None, cfg.scale))

    img = ee.Image.cat([con("forest_bin").rename("conect_forest"),
                        con("natural_bin").rename("conect_natural")])
    return img.toInt16().set({"year": year, "stage": "conn"})


def build_s3_distance(cfg: Config, year: int) -> ee.Image:
    c = ee.Image(f"{cfg.coll('conn')}/conn_{year}").select("conect_natural")
    bands = []
    for s in cfg.source_sizes:
        src = c.gte(s)  # original: natural conect >= S
        dist = src.distance(ee.Kernel.euclidean(cfg.max_distance_m, "meters"))
        dist = ee.Image(cfg.no_source_value).blend(dist)   # original: brazil_25k.blend(dist)
        bands.append(dist.rename(f"dist_s{s}"))
    return ee.Image.cat(bands).toInt16().set({"year": year, "stage": "distance"})


def build_s4_isolation(cfg: Config, year: int) -> ee.Image:
    conn = ee.Image(f"{cfg.coll('conn')}/conn_{year}")
    dist = ee.Image(f"{cfg.coll('distance')}/distance_{year}")
    lulc = ee.Image(f"{cfg.coll('masks')}/masks_{year}").select("lulc")
    kernel = ee.Kernel.plus(1) if cfg.target_connectedness == "plus" else ee.Kernel.square(1)
    uso_from = cfg.uso_classes

    bands = []
    for t in cfg.target_sizes:
        # original: forest conect <= T  OR  natural conect <= T
        frag = (conn.select("conect_forest").lte(t).unmask(0)
                .Or(conn.select("conect_natural").lte(t).unmask(0))).selfMask()
        comp = frag.connectedComponents(connectedness=kernel, maxSize=550)
        labels = comp.select("labels")
        inside = comp.select(0).eq(1)
        for s in cfg.source_sizes:
            if cfg.skip_source_le_target and s <= t:
                continue
            min_dist = (dist.select(f"dist_s{s}").rename("distance").updateMask(inside)
                        .addBands(labels)
                        .reduceConnectedComponents(ee.Reducer.min(), "labels", 256))
            for d in cfg.distances_m:
                isolated = min_dist.gt(d)   # original: > 5000 / 10000 / 20000
                uso = lulc.updateMask(isolated).remap(uso_from, uso_from)
                bands.append(uso.rename(band_name(t, s, d)))
    return ee.Image.cat(bands).toByte().set({"year": year, "stage": "isolation"})


def build_s5_stats(cfg: Config, year: int) -> ee.FeatureCollection:
    """Forest area (ha) at 30 m inside isolated targets, by biome x LULC class.

    One reduceRegion pass: band 0 = forest reference, bands 1..n = combos,
    grouped by territory = biome * 100 + LULC class (30 m).
    """
    lulc30 = ee.Image(cfg.lulc_asset).select(f"classification_{year}")
    forest = lulc30.remap(cfg.paper_forest_classes, [1] * len(cfg.paper_forest_classes), 0)
    biomes = ee.Image(cfg.biomes_asset)
    territory = biomes.multiply(100).add(lulc30).rename("territory").toInt32()
    iso = ee.Image(f"{cfg.coll('isolation')}/isolation_{year}")
    area = ee.Image.pixelArea().divide(1e4)

    names = [band_name(*c) for c in cfg.combos()]
    stack = [area.rename("ref_ha")]
    for n in names:
        stack.append(area.multiply(iso.select(n).gt(0).unmask(0)).rename(n))
    img = ee.Image.cat(stack).updateMask(forest).addBands(territory)
    n_vals = len(stack)
    res = img.reduceRegion(
        reducer=ee.Reducer.sum().repeat(n_vals).group(groupField=n_vals, groupName="territory"),
        geometry=_region(cfg), scale=cfg.stats_scale, maxPixels=1e13, tileScale=4)
    keys = ["ref_ha"] + names

    def to_feat(g):
        g = ee.Dictionary(g)
        vals = ee.List(g.get("sum"))
        props = ee.Dictionary.fromLists(keys, vals)
        return ee.Feature(None, props.set("territory", g.get("territory")).set("year", year))

    return ee.FeatureCollection(ee.List(res.get("groups")).map(to_feat))


# =============================================================================
# Job plan
# =============================================================================


@dataclass
class Job:
    key: str                      # unique, also the task description
    stage: str
    year: int
    target: str                   # asset id (or Drive file name for drive jobs)
    deps: List[str]               # keys of jobs that must be COMPLETED first
    make_task: Callable[[], "ee.batch.Task"]
    is_asset: bool = True
    state: str = "PENDING"        # PENDING | RUNNING | COMPLETED | FAILED | SKIPPED
    task_id: Optional[str] = None
    attempts: int = 0
    error: Optional[str] = None


def plan_jobs(cfg: Config, years: Optional[List[int]] = None) -> Dict[str, Job]:
    years = years or cfg.years
    region = _region(cfg)
    jobs: Dict[str, Job] = {}

    def img_job(stage, y, builder, deps, pyramid="mode"):
        coll = cfg.coll(stage)
        aid = f"{coll}/{stage}_{y}"
        key = f"iso11_{stage}_{y}_v{cfg.version}"

        def mk():
            return ee.batch.Export.image.toAsset(
                image=builder(cfg, y), description=key, assetId=aid, region=region,
                scale=cfg.scale, crs=cfg.crs, maxPixels=1e13,
                pyramidingPolicy={".default": pyramid})
        jobs[key] = Job(key, stage, y, aid, deps, mk)
        return key

    for y in years:
        k1 = img_job("masks", y, build_s1_masks, [])
        k2 = img_job("conn", y, build_s2_conn, [k1])
        k3 = img_job("distance", y, build_s3_distance, [k2], pyramid="mean")
        k4 = img_job("isolation", y, build_s4_isolation, [k1, k2, k3])

        key = f"iso11_stats_{y}_v{cfg.version}"
        aid = f"{cfg.stats_folder}/isolation_stats_{y}"

        def mk_stats(y=y, key=key, aid=aid):
            return ee.batch.Export.table.toAsset(
                collection=build_s5_stats(cfg, y), description=key, assetId=aid)
        jobs[key] = Job(key, "stats", y, aid, [k4], mk_stats)

        if cfg.stats_to_drive:
            dkey = f"iso11_statsdrive_{y}_v{cfg.version}"

            def mk_drive(y=y, dkey=dkey):
                cols = ["year", "territory", "ref_ha"] + [band_name(*c) for c in cfg.combos()]
                return ee.batch.Export.table.toDrive(
                    collection=build_s5_stats(cfg, y), description=dkey,
                    folder=cfg.drive_folder, fileNamePrefix=f"isolation_forest_col11_{y}",
                    fileFormat="CSV", selectors=cols)
            jobs[dkey] = Job(dkey, "stats_drive", y, f"drive:{dkey}", [k4], mk_drive,
                             is_asset=False)
    return jobs


# =============================================================================
# Scheduler
# =============================================================================

_EE_STATE = {  # Operation states -> Task states
    "PENDING": "RUNNING", "RUNNING": "RUNNING", "CANCELLING": "RUNNING",
    "SUCCEEDED": "COMPLETED", "FAILED": "FAILED", "CANCELLED": "FAILED",
    "READY": "RUNNING", "COMPLETED": "COMPLETED", "CANCEL_REQUESTED": "RUNNING",
}


def _active_operations() -> Dict[str, dict]:
    """description -> {'id','state','error'} for recent export operations (1 API call)."""
    out = {}
    for op in ee.data.listOperations():
        md = op.get("metadata", {})
        desc = md.get("description")
        if not desc:
            continue
        st = _EE_STATE.get(md.get("state", ""), "RUNNING")
        prev = out.get(desc)
        # keep the most recent operation per description
        if prev is None or md.get("createTime", "") > prev["createTime"]:
            out[desc] = {"id": op["name"].split("/")[-1], "state": st,
                         "error": op.get("error", {}).get("message"),
                         "createTime": md.get("createTime", "")}
    return out


def _log(cfg: Config, **rec):
    rec["time"] = datetime.utcnow().isoformat(timespec="seconds")
    with open(cfg.log_file, "a") as f:
        f.write(json.dumps(rec) + "\n")


def _summary(jobs: Dict[str, Job]) -> str:
    stages = ["masks", "conn", "distance", "isolation", "stats", "stats_drive"]
    lines = []
    for s in stages:
        js = [j for j in jobs.values() if j.stage == s]
        if not js:
            continue
        c = {k: sum(j.state == k for j in js) for k in
             ("COMPLETED", "SKIPPED", "RUNNING", "PENDING", "FAILED")}
        lines.append(f"{s:<12} done {c['COMPLETED'] + c['SKIPPED']:>3}/{len(js):<3} "
                     f"running {c['RUNNING']:>3}  waiting {c['PENDING']:>3}  failed {c['FAILED']:>2}")
    return "\n".join(lines)


def run_pipeline(cfg: Config, years: Optional[List[int]] = None,
                 dry_run: bool = False, verbose: bool = True) -> Dict[str, Job]:
    """Build, launch and monitor every export until all are done or failed.

    Safe to re-run: existing assets are skipped (unless cfg.overwrite) and tasks
    already running with the same description are re-attached, not duplicated.
    """
    for name in ("masks", "conn", "distance", "isolation"):
        ensure_container(cfg.coll(name), "IMAGE_COLLECTION")
    ensure_container(cfg.stats_folder, "FOLDER")

    jobs = plan_jobs(cfg, years)
    ops = _active_operations()

    # resume: mark existing outputs and re-attach running tasks
    for j in jobs.values():
        if j.is_asset and not cfg.overwrite and asset_exists(j.target):
            j.state = "SKIPPED"
        elif j.key in ops and ops[j.key]["state"] == "RUNNING":
            j.state, j.task_id = "RUNNING", ops[j.key]["id"]
        elif (not j.is_asset) and j.key in ops and ops[j.key]["state"] == "COMPLETED":
            j.state = "SKIPPED"

    if dry_run:
        print(f"{len(jobs)} jobs planned (dry run)\n" + _summary(jobs))
        return jobs

    done_states = {"COMPLETED", "SKIPPED"}
    t0 = time.time()
    while True:
        # 1) refresh running tasks (one listOperations call)
        running = [j for j in jobs.values() if j.state == "RUNNING"]
        if running:
            ops = _active_operations()
            for j in running:
                op = ops.get(j.key)
                if op is None or op["id"] != j.task_id:
                    continue
                if op["state"] == "COMPLETED":
                    j.state = "COMPLETED"
                    _log(cfg, key=j.key, state="COMPLETED")
                elif op["state"] == "FAILED":
                    j.error = op["error"]
                    if j.attempts <= cfg.max_retries:
                        j.state = "PENDING"            # retry
                        _log(cfg, key=j.key, state="RETRY", error=j.error)
                    else:
                        j.state = "FAILED"
                        _log(cfg, key=j.key, state="FAILED", error=j.error)
                        print(f"FAILED {j.key}: {j.error}")

        # 2) start every ready job, up to the concurrency limit
        n_running = sum(j.state == "RUNNING" for j in jobs.values())
        for j in jobs.values():
            if n_running >= cfg.max_concurrent:
                break
            if j.state != "PENDING":
                continue
            if any(jobs[d].state not in done_states for d in j.deps if d in jobs):
                if any(jobs[d].state == "FAILED" for d in j.deps if d in jobs):
                    j.state, j.error = "FAILED", "dependency failed"
                continue
            if j.is_asset and asset_exists(j.target):   # half-written retry
                if cfg.overwrite or j.attempts > 0:
                    ee.data.deleteAsset(j.target)
                else:
                    j.state = "SKIPPED"
                    continue
            try:
                task = j.make_task()
                task.start()
                j.task_id, j.state = task.id, "RUNNING"
                j.attempts += 1
                n_running += 1
                _log(cfg, key=j.key, state="STARTED", task_id=task.id, attempt=j.attempts)
            except ee.EEException as e:       # e.g. quota: try again next poll
                j.error = str(e)
                _log(cfg, key=j.key, state="START_ERROR", error=j.error)
                break

        # 3) report and stop when nothing is left
        if verbose:
            mins = (time.time() - t0) / 60
            print(f"\n[{datetime.now():%H:%M:%S}] elapsed {mins:5.1f} min\n{_summary(jobs)}",
                  flush=True)
        if all(j.state in done_states | {"FAILED"} for j in jobs.values()):
            break
        time.sleep(cfg.poll_seconds)

    failed = [j for j in jobs.values() if j.state == "FAILED"]
    print("\nFINISHED." + (f" {len(failed)} failed:" if failed else " All jobs done."))
    for j in failed:
        print(f"  {j.key}: {j.error}")
    return jobs


def config_as_dict(cfg: Config) -> dict:
    return dataclasses.asdict(cfg)
