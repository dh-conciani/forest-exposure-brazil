"""
isolation3.py - Habitat isolation of FOREST, MapBiomas Collection 11, 1986-2024.
Self-managed Earth Engine pipeline for Google Colab (same method as
gee/col11/isolation_forest_col11.js, commit c6dcaba).

Per year, 3 chained exports:
  STEP 1  s1_100m  heavy part at 100 m (EPSG:5880): distance to source patches,
                   target patches (8-neighbour), minimum distance per target patch.
                   -> ImageCollection forest_isolation_100m (9 uint8 bands s<S>_t<T>)
  STEP 2  s2_30m   30 m maps (EPSG:4326): 100 m classes restricted to forest pixels
                   of target patches -> ImageCollection forest_isolation (paper/platform)
  STEP 3  s3_table area table (CSV to Drive, same format as the JS):
                   year, territory (biome*100 + LULC class), source_ha, target_ha,
                   dist_class (LOWER threshold, m; 0 = reference forest), area_ha

The scheduler starts a year's step 2 and 3 as soon as its step 1 asset exists,
polls Earth Engine, retries failures (not timeouts), respects max_concurrent and
is safe to re-run: existing assets are skipped, running tasks re-attached, and
step-3 tasks already SUCCEEDED (by description) are not repeated.
"""
from __future__ import annotations

import dataclasses
import json
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Callable, Dict, List, Optional

import ee

ROOT = "projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11"


@dataclass
class Config:
    lulc: str = "projects/mapbiomas-public/assets/brazil/lulc/collection11/mapbiomas_brazil_collection11_coverage_v3"
    patch_size: str = f"{ROOT}/area"                    # ImageCollection, 1 image/year, 1 band (ha)
    patch_prefix: str = "degradation_patch_size_col11_"
    patch_suffix: str = "_v1"
    # biome raster: 1 Amazonia, 2 Mata Atlantica, 3 Pantanal, 4 Cerrado, 5 Caatinga, 6 Pampa
    biomes: str = "projects/mapbiomas-workspace/AUXILIAR/biomas-2019-raster_old"
    years: List[int] = field(default_factory=lambda: list(range(1986, 2025)))
    source_sizes: List[int] = field(default_factory=lambda: [100, 500, 1000])   # ha, >=
    target_sizes: List[int] = field(default_factory=lambda: [25, 50, 100])      # ha, <=
    distances: List[int] = field(default_factory=lambda: [500, 1000, 2000, 5000, 10000])  # m
    forest_classes: List[int] = field(default_factory=lambda: [3, 5, 6, 49])
    work_scale: int = 100
    work_crs: str = "EPSG:5880"
    collection100: str = f"{ROOT}/isolation/forest_isolation_100m"
    prefix100: str = "degradation_forest_isolation_100m_col11_"
    collection30: str = f"{ROOT}/isolation/forest_isolation"
    prefix30: str = "degradation_forest_isolation_col11_"
    version: str = "1"
    drive_folder: str = "PAPER-DEGRAD-COL11"
    steps: List[int] = field(default_factory=lambda: [1, 2, 3])
    table_from_30m: bool = True       # step 3 waits for step 2 (cheapest reduction)
    tile_scale: int = 4
    max_concurrent: int = 1500
    poll_seconds: int = 60
    max_retries: int = 2              # timeouts (Error code 3) are NOT retried
    log_file: str = "isolation3_log.jsonl"
    lookback_hours: int = 72          # tasks older than this are ignored (resume window)
    max_pages: int = 20               # max pages of 500 operations read per poll

    def combos(self):
        return [(s, t) for t in self.target_sizes for s in self.source_sizes]

    def id100(self, y):
        return f"{self.collection100}/{self.prefix100}{y}_v{self.version}"

    def id30(self, y):
        return f"{self.collection30}/{self.prefix30}{y}_v{self.version}"


# =============================================================================
# Builders (identical logic to isolation_forest_col11.js)
# =============================================================================

def _legend(cfg):
    out = []
    for i, d in enumerate(cfg.distances):
        hi = cfg.distances[i + 1] if i + 1 < len(cfg.distances) else None
        out.append(f"{i + 1} = {d}" + (f"-{hi}" if hi else "+") + " m")
    return "; ".join(out)


def _proj100(cfg):
    return ee.Projection(cfg.work_crs).atScale(cfg.work_scale)


def _geometry(cfg):
    return ee.Image(cfg.biomes).geometry()


def patch_size(cfg, y):
    return ee.Image(f"{cfg.patch_size}/{cfg.patch_prefix}{y}{cfg.patch_suffix}").select(0).rename("size")


def forest(cfg, y):
    return (ee.Image(cfg.lulc).select(f"classification_{y}")
            .remap(cfg.forest_classes, [1] * len(cfg.forest_classes), 0).selfMask())


def _to100(cfg, mask30):
    return (mask30.unmask(0).reduceResolution(reducer=ee.Reducer.max(), maxPixels=64)
            .reproject(_proj100(cfg)))


def _distance(cfg, src100):
    return (src100.fastDistanceTransform(256, "pixels", "squared_euclidean")
            .sqrt().multiply(cfg.work_scale).reproject(_proj100(cfg)))


def _props(cfg, y, scale):
    return {
        "system:time_start": ee.Date.fromYMD(y, 1, 1).millis(),
        "system:time_end": ee.Date.fromYMD(y + 1, 1, 1).millis(),
        "year": y, "collection": 11, "version": cfg.version, "theme": "isolation",
        "scale_m": scale, "biome_scope": "BRAZIL", "lulc_asset": cfg.lulc,
        "patch_size_asset": cfg.patch_size,
        "forest_classes": ",".join(map(str, cfg.forest_classes)),
        "source_sizes_ha": ",".join(map(str, cfg.source_sizes)),
        "target_sizes_ha": ",".join(map(str, cfg.target_sizes)),
        "distances_m": ",".join(map(str, cfg.distances)),
        "work_crs": cfg.work_crs, "work_scale_m": cfg.work_scale,
        "values": _legend(cfg) + " from nearest source patch; masked = not isolated",
    }


def build_step1(cfg, y):
    size = patch_size(cfg, y)
    dist = {s: _distance(cfg, _to100(cfg, size.gte(s).selfMask())) for s in cfg.source_sizes}
    bands = []
    for t in cfg.target_sizes:
        target100 = _to100(cfg, size.lte(t).selfMask()).selfMask()
        labels = target100.connectedComponents(ee.Kernel.square(1), 256).select("labels")
        for s in cfg.source_sizes:
            min_dist = (dist[s].addBands(labels)
                        .reduceConnectedComponents(ee.Reducer.min(), "labels", 256)
                        .reproject(_proj100(cfg)))
            cls = ee.Image(0)
            for i, d in enumerate(cfg.distances):
                cls = cls.where(min_dist.gte(d), i + 1)
            bands.append(cls.updateMask(target100).selfMask().toByte().rename(f"s{s}_t{t}"))
    return ee.Image.cat(bands).set(_props(cfg, y, cfg.work_scale))


def build_step2(cfg, y, img100=None):
    img100 = img100 or ee.Image(cfg.id100(y))
    size, fo = patch_size(cfg, y), forest(cfg, y)
    bands = []
    for t in cfg.target_sizes:
        target30 = size.lte(t)
        for s in cfg.source_sizes:
            b = f"s{s}_t{t}"
            bands.append(img100.select(b).updateMask(target30).updateMask(fo).rename(b))
    return ee.Image.cat(bands).toByte().set(_props(cfg, y, 30))


TABLE_COLS = ["year", "territory", "source_ha", "target_ha", "dist_class", "area_ha"]


def build_step3(cfg, y):
    img30 = ee.Image(cfg.id30(y)) if cfg.table_from_30m else build_step2(cfg, y)
    lulc_y = ee.Image(cfg.lulc).select(f"classification_{y}")
    territory = ee.Image(cfg.biomes).multiply(100).add(lulc_y).rename("territory")
    area = ee.Image.pixelArea().divide(10000)
    bands, specs = [area.updateMask(forest(cfg, y))], [(0, 0, 0)]
    for s, t in cfg.combos():
        b = img30.select(f"s{s}_t{t}")
        for i, d in enumerate(cfg.distances):
            bands.append(area.updateMask(b.eq(i + 1)))
            specs.append((s, t, d))
    n = len(bands)
    st = ee.Image.cat(bands).addBands(territory).reduceRegion(
        reducer=ee.Reducer.sum().repeat(n).group(n, "territory"),
        geometry=_geometry(cfg), scale=30, maxPixels=1e13, tileScale=cfg.tile_scale)

    def feats(g):
        g = ee.Dictionary(g)
        sums = ee.List(g.get("sum"))
        return ee.List([ee.Feature(None, {"year": y, "territory": g.get("territory"),
                                          "source_ha": sp[0], "target_ha": sp[1],
                                          "dist_class": sp[2], "area_ha": sums.get(k)})
                        for k, sp in enumerate(specs)])
    fc = ee.FeatureCollection(ee.List(st.get("groups")).map(feats).flatten())
    return fc.filter(ee.Filter.gt("area_ha", 0))


# =============================================================================
# Assets
# =============================================================================

def asset_exists(asset_id):
    try:
        ee.data.getAsset(asset_id)
        return True
    except ee.EEException:
        return False


def list_ids(coll):
    try:
        assets = ee.data.listAssets({"parent": coll}).get("assets", [])
        return {a.get("id", "") for a in assets} | {a.get("name", "") for a in assets}
    except ee.EEException:
        return set()


def ensure_container(asset_id, kind="IMAGE_COLLECTION"):
    if asset_exists(asset_id):
        return
    parent = asset_id.rsplit("/", 1)[0]
    if parent.count("/") >= 3 and not asset_exists(parent):
        ensure_container(parent, "FOLDER")
    ee.data.createAsset({"type": kind}, asset_id)
    print(f"created {kind}: {asset_id}")


def check_inputs(cfg, years=None):
    """Fail fast: input assets, LULC bands and patch-size images for every year."""
    years = years or cfg.years
    for a in (cfg.lulc, cfg.biomes, cfg.patch_size):
        if not asset_exists(a):
            raise ValueError(f"Input asset not found or no access: {a}")
    bands = ee.Image(cfg.lulc).bandNames().getInfo()
    miss = [y for y in years if f"classification_{y}" not in bands]
    have = list_ids(cfg.patch_size)
    miss_ps = [y for y in years if not any(i.endswith(f"{cfg.patch_prefix}{y}{cfg.patch_suffix}") for i in have)]
    if miss or miss_ps:
        raise ValueError(f"Missing LULC years {miss}; missing patch-size years {miss_ps}")
    print(f"inputs OK for {len(years)} years")


# =============================================================================
# Jobs and scheduler
# =============================================================================

@dataclass
class Job:
    key: str                      # task description (unique)
    step: int
    year: int
    target: str                   # asset id or 'drive:<name>'
    deps: List[str]
    make_task: Callable[[], "ee.batch.Task"]
    is_asset: bool = True
    state: str = "PENDING"        # PENDING | RUNNING | COMPLETED | SKIPPED | FAILED
    task_id: Optional[str] = None
    attempts: int = 0
    error: Optional[str] = None


def plan_jobs(cfg, years=None):
    years = years or cfg.years
    region = _geometry(cfg)
    jobs: Dict[str, Job] = {}
    for y in years:
        k1 = f"{cfg.prefix100}{y}_v{cfg.version}"
        k2 = f"{cfg.prefix30}{y}_v{cfg.version}"
        k3 = f"isolation_forest_col11_{y}"
        if 1 in cfg.steps:
            jobs[k1] = Job(k1, 1, y, cfg.id100(y), [], lambda y=y, k=k1: ee.batch.Export.image.toAsset(
                image=build_step1(cfg, y), description=k, assetId=cfg.id100(y), region=region,
                crs=cfg.work_crs, scale=cfg.work_scale, maxPixels=1e13,
                pyramidingPolicy={".default": "mode"}))
        if 2 in cfg.steps:
            jobs[k2] = Job(k2, 2, y, cfg.id30(y), [k1], lambda y=y, k=k2: ee.batch.Export.image.toAsset(
                image=build_step2(cfg, y), description=k, assetId=cfg.id30(y), region=region,
                crs="EPSG:4326", scale=30, maxPixels=1e13, pyramidingPolicy={".default": "mode"}))
        if 3 in cfg.steps:
            deps = [k1] + ([k2] if cfg.table_from_30m else [])
            jobs[k3] = Job(k3, 3, y, f"drive:{k3}", deps, lambda y=y, k=k3: ee.batch.Export.table.toDrive(
                collection=build_step3(cfg, y), description=k, folder=cfg.drive_folder,
                fileNamePrefix=k, fileFormat="CSV", selectors=TABLE_COLS), is_asset=False)
    return jobs


_STATE = {"PENDING": "RUNNING", "READY": "RUNNING", "RUNNING": "RUNNING",
          "CANCELLING": "RUNNING", "CANCEL_REQUESTED": "RUNNING",
          "SUCCEEDED": "COMPLETED", "COMPLETED": "COMPLETED",
          "FAILED": "FAILED", "CANCELLED": "FAILED"}


def operations(since=None, max_pages=20):
    """description -> most recent operation {'id','state','error','createTime'}.

    Reads only RECENT operations (newest first, pages of 500) and stops at the first
    page older than `since` (ISO UTC) or after `max_pages`. ee.data.listOperations()
    would page through the whole history of a shared project (very slow).
    """
    out = {}
    proj = ee.data._get_projects_path()
    api = ee.data._get_cloud_projects()
    req = api.operations().list(name=proj, pageSize=500)
    pages = 0
    while req is not None and pages < max_pages:
        resp = ee.data._execute_cloud_call(req)
        pages += 1
        page = resp.get("operations", [])
        for op in page:
            md = op.get("metadata", {})
            d = md.get("description")
            if not d:
                continue
            rec = {"id": op["name"].split("/")[-1], "state": _STATE.get(md.get("state", ""), "RUNNING"),
                   "error": (op.get("error") or {}).get("message"), "createTime": md.get("createTime", "")}
            if d not in out or rec["createTime"] > out[d]["createTime"]:
                out[d] = rec
        times = [op.get("metadata", {}).get("createTime", "") for op in page]
        if since and times and max(times) < since:
            break                                   # whole page older than the window
        req = api.operations().list_next(req, resp)
    return out


def _log(cfg, **rec):
    rec["time"] = datetime.utcnow().isoformat(timespec="seconds")
    with open(cfg.log_file, "a") as f:
        f.write(json.dumps(rec) + "\n")


def summary(jobs):
    names = {1: "step1 100m", 2: "step2 30m", 3: "step3 table"}
    lines = []
    for s in (1, 2, 3):
        js = [j for j in jobs.values() if j.step == s]
        if js:
            c = {k: sum(j.state == k for j in js) for k in ("COMPLETED", "SKIPPED", "RUNNING", "PENDING", "FAILED")}
            lines.append(f"{names[s]:<12} done {c['COMPLETED'] + c['SKIPPED']:>3}/{len(js):<3} running {c['RUNNING']:>3}"
                         f"  waiting {c['PENDING']:>3}  failed {c['FAILED']:>2}")
    return "\n".join(lines)


def _is_timeout(err):
    return bool(err) and ("timed out" in err.lower() or "error code: 3" in err.lower())


def run(cfg, years=None, dry_run=False, verbose=True):
    """Launch and monitor all steps until every job is done or failed. Safe to re-run."""
    for c in (cfg.collection100, cfg.collection30):
        ensure_container(c)
    jobs = plan_jobs(cfg, years)
    since = (datetime.utcnow() - timedelta(hours=cfg.lookback_hours)).isoformat() + "Z"
    print("reading recent tasks ...", flush=True)
    ops = operations(since, cfg.max_pages)
    have = list_ids(cfg.collection100) | list_ids(cfg.collection30)
    for j in jobs.values():
        op = ops.get(j.key)
        if j.is_asset and j.target in have:
            j.state = "SKIPPED"
        elif op and op["state"] == "RUNNING":
            j.state, j.task_id = "RUNNING", op["id"]
        elif not j.is_asset and op and op["state"] == "COMPLETED":
            j.state = "SKIPPED"
    print(f"{len(jobs)} jobs planned; starting up to {cfg.max_concurrent} at once", flush=True)
    if dry_run:
        print(f"{len(jobs)} jobs planned (dry run)\n" + summary(jobs))
        return jobs

    ok = {"COMPLETED", "SKIPPED"}
    t0 = time.time()
    while True:
        running = [j for j in jobs.values() if j.state == "RUNNING"]
        if running:
            ops = operations(since, cfg.max_pages)
            for j in running:
                op = ops.get(j.key)
                if not op or op["id"] != j.task_id:
                    continue
                if op["state"] == "COMPLETED":
                    j.state = "COMPLETED"
                    _log(cfg, key=j.key, state="COMPLETED")
                elif op["state"] == "FAILED":
                    j.error = op["error"]
                    if j.attempts <= cfg.max_retries and not _is_timeout(j.error):
                        j.state = "PENDING"
                        _log(cfg, key=j.key, state="RETRY", error=j.error)
                    else:
                        j.state = "FAILED"
                        _log(cfg, key=j.key, state="FAILED", error=j.error)
                        print(f"FAILED {j.key}: {j.error}")

        n_run = sum(j.state == "RUNNING" for j in jobs.values())
        # step 1 first, then 2, then 3, oldest year first
        for j in sorted(jobs.values(), key=lambda j: (j.step, j.year)):
            if n_run >= cfg.max_concurrent:
                break
            if j.state != "PENDING":
                continue
            dep_jobs = [jobs[d] for d in j.deps if d in jobs]
            if any(d.state == "FAILED" for d in dep_jobs):
                j.state, j.error = "FAILED", "dependency failed"
                continue
            if any(d.state not in ok for d in dep_jobs):
                continue
            # dependency not planned in this run (e.g. steps=[2,3]): need its asset
            missing = [d for d in j.deps if d not in jobs and not asset_exists(
                cfg.id100(j.year) if d.startswith(cfg.prefix100) else cfg.id30(j.year))]
            if missing:
                continue
            if j.is_asset and asset_exists(j.target):
                if j.attempts > 0:
                    ee.data.deleteAsset(j.target)          # half-written retry
                else:
                    j.state = "SKIPPED"
                    continue
            try:
                task = j.make_task()
                task.start()
                j.task_id, j.state = task.id, "RUNNING"
                j.attempts += 1
                n_run += 1
                _log(cfg, key=j.key, state="STARTED", task_id=task.id, attempt=j.attempts)
            except ee.EEException as e:                    # quota etc.: retry next poll
                j.error = str(e)
                _log(cfg, key=j.key, state="START_ERROR", error=j.error)
                break

        if verbose:
            print(f"\n[{datetime.now():%H:%M:%S}] {(time.time() - t0) / 60:6.1f} min\n{summary(jobs)}", flush=True)
        if all(j.state in ok | {"FAILED"} for j in jobs.values()):
            break
        if n_run == 0:
            print("Nothing running and nothing can start (missing upstream assets?). Stopping.")
            break
        time.sleep(cfg.poll_seconds)

    failed = [j for j in jobs.values() if j.state == "FAILED"]
    print("\nFINISHED." + (f" {len(failed)} failed:" if failed else " All jobs done."))
    for j in failed:
        print(f"  {j.key}: {j.error}")
    if any(_is_timeout(j.error) for j in failed):
        print("Timeouts are not retried (same computation). Split the work (e.g. by biome) and re-run.")
    return jobs
