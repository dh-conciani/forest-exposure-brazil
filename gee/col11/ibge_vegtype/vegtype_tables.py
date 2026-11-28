"""
Box 1 / Table S8 (Collection 11): forest area exposed to each degradation driver by
IBGE vegetation type, in the same exclusive-class format as the Col. 9 tables
(data/raw/ibge_vegetation/area_<driver>_ibge_c9.csv), for the ranking years.

Outputs (Google Drive, folder Config.drive_folder), one CSV per driver:
  area_reference_ibge_c11  forest area                         class_id = 1
  area_edge_ibge_c11       distance to anthropogenic edge (m)  class_id = upper bound (30..1000)
  area_patch_ibge_c11      native-vegetation patch size (ha)   class_id = upper bound (5..100)
  area_isolation_ibge_c11  isolation, main scenario            class_id = lower bound in km
  area_firecount_ibge_c11  number of fires since 1985          class_id = count (1..)
Columns: territory (IBGE vegetation id), year, class_id, area (ha).

Forest = MapBiomas LULC Col. 11 classes 3, 5, 6, 49 of the same year. All areas with
ee.Image.pixelArea() at 30 m (MapBiomas grid).

BEFORE RUNNING: set the two module assets marked CONFIRM (edge distance and fire
frequency). `discover()` lists what exists under the Col. 11 degradation root.

Colab:
    import ee; ee.Authenticate(); ee.Initialize(project="<your-project>")
    import vegtype_tables as vt
    vt.discover()                      # find the edge / fire assets
    cfg = vt.Config(edge=..., fire=...)
    vt.run(cfg)                        # starts 5 Drive exports
"""
from dataclasses import dataclass, field
from typing import Callable, List
import ee

ROOT = "projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11"


@dataclass
class Config:
    lulc: str = "projects/mapbiomas-public/assets/brazil/lulc/collection11/mapbiomas_brazil_collection11_coverage_v3"
    ibge_veg: str = ("projects/mapbiomas-territories/assets/TERRITORIES/LULC/BRAZIL/COLLECTION9/"
                     "WORKSPACE/INFORMACAO_AMBIENTAL_VEGETACAO_IBGE_raster")
    # patch size (ha), 1 image/year, band 0 - same product used by the isolation pipeline
    patch: Callable[[int], ee.Image] = lambda y: ee.Image(
        f"{ROOT}/area/degradation_patch_size_col11_{y}_v1").select(0)
    # CONFIRM: distance (m) from each forest pixel to the nearest anthropogenic pixel, year y
    edge: Callable[[int], ee.Image] = None
    # CONFIRM: number of years burned since 1985 up to year y (MapBiomas Fire Col. 5)
    fire: Callable[[int], ee.Image] = None
    # isolation 30 m maps from the 3-step pipeline; band of the main scenario
    isolation: Callable[[int], ee.Image] = lambda y: ee.Image(
        f"{ROOT}/isolation/forest_isolation/degradation_forest_isolation_col11_{y}_v1").select("s1000_t100")
    isolation_km: List[float] = field(default_factory=lambda: [0.5, 1, 2, 5, 10])  # codes 1..5
    edge_m: List[int] = field(default_factory=lambda: [30, 60, 90, 120, 150, 300, 600, 1000])
    patch_ha: List[int] = field(default_factory=lambda: [5, 10, 25, 50, 100])
    years: List[int] = field(default_factory=lambda: [2010, 2024])
    forest_classes: List[int] = field(default_factory=lambda: [3, 5, 6, 49])
    scale: int = 30
    tile_scale: int = 4
    drive_folder: str = "PAPER-DEGRAD-COL11"


def discover(root: str = ROOT, depth: int = 2):
    """Print assets under the Col. 11 degradation root (to fill Config.edge / Config.fire)."""
    def walk(parent, d):
        for a in ee.data.listAssets({"parent": parent}).get("assets", []):
            print("  " * (depth - d) + f"{a['type']:<17} {a['id']}")
            if d > 1 and a["type"] == "FOLDER":
                walk(a["id"], d - 1)
    walk(root, depth)


def _bin_upper(img, bounds):
    """value -> smallest upper bound >= value (exclusive classes), masked above max."""
    out = ee.Image(0)
    for b in reversed(bounds):
        out = out.where(img.lte(b), b)
    return out.updateMask(img.lte(bounds[-1])).toInt()


def _forest(cfg, y):
    lulc = ee.Image(cfg.lulc).select(f"classification_{y}")
    return lulc.remap(cfg.forest_classes, [1] * len(cfg.forest_classes), 0).selfMask()


def _classed(cfg, driver, y):
    f = _forest(cfg, y)
    if driver == "reference":
        return f
    if driver == "edge":
        return _bin_upper(cfg.edge(y), cfg.edge_m).updateMask(f)
    if driver == "patch":
        return _bin_upper(cfg.patch(y), cfg.patch_ha).updateMask(f)
    if driver == "isolation":   # codes 1..N -> lower bound in km (x1000 to keep integers)
        codes = list(range(1, len(cfg.isolation_km) + 1))
        km1000 = [int(k * 1000) for k in cfg.isolation_km]
        return cfg.isolation(y).remap(codes, km1000).selfMask().updateMask(f)
    if driver == "firecount":
        return cfg.fire(y).toInt().selfMask().updateMask(f)
    raise ValueError(driver)


def _table(cfg, driver, y):
    terr = ee.Image(cfg.ibge_veg).rename("territory")
    cls = _classed(cfg, driver, y).rename("class_id")
    area = ee.Image.pixelArea().divide(1e4).rename("area")
    stats = area.addBands(cls).addBands(terr).reduceRegion(
        reducer=ee.Reducer.sum().group(1, "class_id").group(1, "territory"),
        geometry=terr.geometry(), scale=cfg.scale, maxPixels=1e13, tileScale=cfg.tile_scale)

    def per_terr(t):
        t = ee.Dictionary(t)
        return ee.FeatureCollection(ee.List(t.get("groups")).map(lambda g: ee.Feature(None, {
            "territory": t.get("territory"), "year": y,
            "class_id": ee.Dictionary(g).get("class_id"), "area": ee.Dictionary(g).get("sum")})))
    return ee.FeatureCollection(ee.List(stats.get("groups")).map(per_terr)).flatten()


def run(cfg: Config, drivers=("reference", "edge", "patch", "isolation", "firecount")):
    if "edge" in drivers and cfg.edge is None:
        raise ValueError("Set Config.edge (distance-to-edge image per year). Use discover().")
    if "firecount" in drivers and cfg.fire is None:
        raise ValueError("Set Config.fire (fire count since 1985 per year). Use discover().")
    tasks = []
    for d in drivers:
        fc = ee.FeatureCollection([_table(cfg, d, y) for y in cfg.years]).flatten()
        name = f"area_{d}_ibge_c11"
        t = ee.batch.Export.table.toDrive(collection=fc, description=name, folder=cfg.drive_folder,
                                          fileNamePrefix=name, fileFormat="CSV",
                                          selectors=["territory", "year", "class_id", "area"])
        t.start(); tasks.append(t); print("started", name)
    return tasks
