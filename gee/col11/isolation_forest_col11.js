/* =============================================================================
 * isolation_forest_col11.js
 * Habitat isolation of FOREST for the paper, on the MapBiomas Collection 11
 * degradation inputs, exported as area tables ready for the R pipeline.
 *
 * Same conceptual rule as the Degradation Module ATBD v2, section 2.6:
 *   a forest pixel is "isolated" when it belongs to a TARGET native-vegetation
 *   patch (<= 25 / 50 / 100 ha) whose nearest SOURCE patch (>= 100 / 500 / 1000 ha)
 *   is >= 0.5 / 1 / 2 / 5 / 10 km away (CONFIG.distances).
 *
 * What changes relative to the Collection 9 workflow (answers R2 3.1, 3.2, 3.3):
 *   1. Patch sizes come from the module's patch-size asset (GRASS r.clump,
 *      8-neighbour, TRUE pixel area in ha). No connectedPixelCount() and no
 *      1,024-pixel limit: sources >= 1000 ha are exact.
 *   2. Distances are computed in an equal-area metric projection
 *      (SIRGAS 2000 / Brazil Polyconic, EPSG:5880) at 100 m, so a "5 km"
 *      threshold means 5 km at every latitude.
 *   3. The target-patch distance is the MINIMUM distance over the patch
 *      (edge-to-edge approximation at 100 m), as in the original workflow.
 *   4. Output = area (ha) of forest by biome x LULC class x year x
 *      source size x target size x distance class, plus forest reference area.
 *
 * HOW TO RUN  (3 steps, same script; change CONFIG.step and press Run again)
 *   STEP 1  heavy part at 100 m (distances, target patches, min distance per patch)
 *           -> ImageCollection forest_isolation_100m, 1 image/year (39 tasks).
 *   STEP 2  30 m maps for the paper/platform: 100 m classes restricted to forest
 *           pixels of target patches -> ImageCollection forest_isolation (39 tasks).
 *   STEP 3  area tables (CSV to Drive): ONE grouped reduction per year on the
 *           stored 30 m map (or derived from the 100 m one) (39 tasks).
 *   Steps 2 and 3 only create tasks for years whose STEP 1 asset exists, so they
 *   can be started as soon as the first 100 m years finish.
 *   Re-running skips tasks already running with the same name and assets that
 *   exist. Containers are created on load. Tip: test with years: [2022] first.
 *   Why: the single-pass version recomputed the whole 100 m chain inside 9 national
 *   30 m reductions per year and hit the 12 h limit (Error code 3).
 *
 * TABLE (Drive CSV, one per year): year, territory (biome*100 + LULC class),
 *   source_ha, target_ha, dist_class, area_ha. dist_class = LOWER distance
 *   threshold in m of an EXCLUSIVE class (0 = reference forest area).
 *
 * MAPS (one image per year, 9 uint8 bands s<S>_t<T>: source >= S ha, target <= T ha):
 *   value i = distance class i (property 'values' gives the legend), masked = not isolated.
 *   forest_isolation_100m: EPSG:5880, 100 m.  forest_isolation: 30 m, EPSG:4326 (forest only).
 * ============================================================================= */

// ------------------------------- CONFIG --------------------------------------
var CONFIG = {
  // TODO: LULC Collection 11 integration asset (bands classification_<year>)
  lulc: 'projects/mapbiomas-public/assets/brazil/lulc/collection11/mapbiomas_brazil_collection11_coverage_v3',
  // Degradation module patch-size ImageCollection (Collection 11): ONE image per year,
  // id <patchSize>/<patchPrefix><year><patchSuffix>, single band = patch size (ha)
  patchSize:   'projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/area',
  patchPrefix: 'degradation_patch_size_col11_',
  patchSuffix: '_v1',
  // Biome raster (IBGE 2019) - same one used for the module statistics
  biomes: 'projects/mapbiomas-workspace/AUXILIAR/biomas-2019-raster_old',
  years: ee.List.sequence(1986, 2024).getInfo(),   // period of the paper
  sourceSizes: [100, 500, 1000],      // ha, source patch >= value
  targetSizes: [25, 50, 100],         // ha, target patch <= value
  // m, ascending, any length (max 25600 = distance cap). Class i = [d_i, d_i+1)
  // (paper default scenario = >= 5 km; finer classes requested by the authors)
  distances:   [500, 1000, 2000, 5000, 10000],
  forestClasses: [3, 5, 6, 49],       // forest formation, mangrove, floodable forest, wooded sandbank
  workScale: 100,                     // m, scale of distance computation
  workCrs: 'EPSG:5880',               // SIRGAS 2000 / Brazil Polyconic (metric)
  driveFolder: 'PAPER-DEGRAD-COL11',
  // --- what to run: 1, then 2 and 3 (see HOW TO RUN) ---
  step: 1,
  collection100: 'projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/isolation/forest_isolation_100m',
  prefix100: 'degradation_forest_isolation_100m_col11_',
  tileScale: 4,                       // step 3 reduction; raise to 8/16 on memory errors
  imageCollection: 'projects/mapbiomas-brazil/assets/DEGRADATION/COLLECTION-11/isolation/forest_isolation',
  imagePrefix: 'degradation_forest_isolation_col11_',  // + <year> + '_v' + version
  version: '1',
  // skip tasks queued/running with the same name (last `recentTasks` tasks; async check)
  // and assets that already exist; set false to ignore running tasks.
  skipCheck: true,
  recentTasks: 300
};

var lulc      = ee.Image(CONFIG.lulc);
// patch size (ha) of one year: the asset is an ImageCollection, not a multiband image
var patchSizeOf = function (year) {
  return ee.Image(CONFIG.patchSize + '/' + CONFIG.patchPrefix + year + CONFIG.patchSuffix)
    .select(0).rename('size');
};
if (CONFIG.distances.length > 254 || CONFIG.distances[CONFIG.distances.length - 1] > 25600) {
  throw new Error('CONFIG.distances: at most 254 thresholds, last one <= 25600 m.');
}
// map value i (1..N) <-> lower threshold (m); stored as image properties
var classLegend = CONFIG.distances.map(function (d, i) {
  var hi = CONFIG.distances[i + 1];
  return (i + 1) + ' = ' + d + (hi ? '-' + hi : '+') + ' m';
}).join('; ');
var biomes    = ee.Image(CONFIG.biomes).rename('biome');
var pixelArea = ee.Image.pixelArea().divide(10000);  // ha (true area)
var geometry  = biomes.geometry();
var proj100   = ee.Projection(CONFIG.workCrs).atScale(CONFIG.workScale);

// 30 m native -> 100 m presence (any 30 m pixel of the mask inside the 100 m cell)
var to100 = function (mask30) {
  return mask30.unmask(0)
    .reduceResolution({reducer: ee.Reducer.max(), maxPixels: 64})
    .reproject(proj100);
};

// Distance (m) from source cells, metric, capped at 25.6 km (256 px x 100 m)
var distanceFrom = function (src100) {
  return src100.fastDistanceTransform(256, 'pixels', 'squared_euclidean')
    .sqrt().multiply(CONFIG.workScale)
    .reproject(proj100);
};

// ---------------------------------------------------------------------------
// STEP 1 (heavy part, 100 m): distance class of each target patch, 9 bands.
// Value i = distance class i at 100 m (masked = not isolated / not target).
var isolation100 = function (year) {
  var size = patchSizeOf(year);               // native patch size, ha
  var dist = {};                              // distance to each source size, computed once
  CONFIG.sourceSizes.forEach(function (s) {
    dist[s] = distanceFrom(to100(size.gte(s).selfMask()));
  });
  var bands = [];
  CONFIG.targetSizes.forEach(function (t) {
    // connected target patches at 100 m (8-neighbour) and their labels
    var target100 = to100(size.lte(t).selfMask()).selfMask();
    var labels = target100.connectedComponents(ee.Kernel.square(1), 256).select('labels');
    CONFIG.sourceSizes.forEach(function (s) {
      // minimum distance over each target patch
      var minDist = dist[s].addBands(labels)
        .reduceConnectedComponents(ee.Reducer.min(), 'labels', 256)
        .reproject(proj100);
      // exclusive distance class: value i where d_i <= minDist < d_i+1
      var cls = ee.Image(0);
      CONFIG.distances.forEach(function (d, i) { cls = cls.where(minDist.gte(d), i + 1); });
      bands.push(cls.updateMask(target100).selfMask().toByte().rename('s' + s + '_t' + t));
    });
  });
  return ee.Image.cat(bands);
};

// STEP 2 (light, 30 m): 100 m classes restricted to forest pixels of target patches.
var isolation30 = function (img100, year) {
  var size = patchSizeOf(year);
  var forest = forestOf(year);
  var bands = [];
  CONFIG.targetSizes.forEach(function (t) {
    var target30 = size.lte(t);
    CONFIG.sourceSizes.forEach(function (s) {
      var b = 's' + s + '_t' + t;
      bands.push(img100.select(b).updateMask(target30).updateMask(forest).rename(b));
    });
  });
  return ee.Image.cat(bands).toByte();
};

var forestOf = function (year) {
  return lulc.select('classification_' + year)
    .remap(CONFIG.forestClasses, ee.List.repeat(1, CONFIG.forestClasses.length), 0).selfMask();
};

var props = function (year, scale) {
  return {
    'system:time_start': ee.Date.fromYMD(year, 1, 1).millis(),
    'system:time_end':   ee.Date.fromYMD(year + 1, 1, 1).millis(),
    year: year, collection: 11, version: CONFIG.version, theme: 'isolation', scale_m: scale,
    biome_scope: 'BRAZIL', lulc_asset: CONFIG.lulc, patch_size_asset: CONFIG.patchSize,
    forest_classes: CONFIG.forestClasses.join(','),
    source_sizes_ha: CONFIG.sourceSizes.join(','), target_sizes_ha: CONFIG.targetSizes.join(','),
    distances_m: CONFIG.distances.join(','), work_crs: CONFIG.workCrs, work_scale_m: CONFIG.workScale,
    values: classLegend + ' from nearest source patch; masked = not isolated'
  };
};

// STEP 3 (table, 30 m): ONE grouped reduction per year on the stored 30 m map:
// bands = reference forest area + area of each (source x target x class) -> sum by territory.
var tableYear = function (img30, year) {
  var lulcY = lulc.select('classification_' + year);
  var forest = forestOf(year);
  var territory = biomes.multiply(100).add(lulcY).rename('territory');
  var bands = [pixelArea.updateMask(forest)];
  var specs = [[0, 0, 0]];                     // [source_ha, target_ha, dist_class (m)]
  CONFIG.targetSizes.forEach(function (t) {
    CONFIG.sourceSizes.forEach(function (s) {
      var b = img30.select('s' + s + '_t' + t);
      CONFIG.distances.forEach(function (d, i) {
        bands.push(pixelArea.updateMask(b.eq(i + 1)));
        specs.push([s, t, d]);
      });
    });
  });
  var n = bands.length;
  var st = ee.Image.cat(bands).addBands(territory).reduceRegion({
    reducer: ee.Reducer.sum().repeat(n).group(n, 'territory'),
    geometry: geometry, scale: 30, maxPixels: 1e13, tileScale: CONFIG.tileScale});
  var feats = ee.List(st.get('groups')).map(function (g) {
    g = ee.Dictionary(g);
    var sums = ee.List(g.get('sum'));
    return ee.List(specs.map(function (sp, k) {
      return ee.Feature(null, {year: year, territory: g.get('territory'), source_ha: sp[0],
                               target_ha: sp[1], dist_class: sp[2], area_ha: sums.get(k)});
    }));
  }).flatten();
  return ee.FeatureCollection(feats).filter(ee.Filter.gt('area_ha', 0));
};

// Create the output folders + ImageCollection if missing (idempotent).
// GEE does NOT create them on export: the task dialog fails with "Asset ... not found".
var assetExists = function (id) {
  try { ee.data.getAsset(id); return true; } catch (e) { return false; }
};
var ensureContainer = function (id, type) {
  if (assetExists(id)) return;
  var parent = id.substring(0, id.lastIndexOf('/'));
  if (parent.split('/').length > 3) ensureContainer(parent, 'FOLDER');   // stop at projects/<p>/assets
  ee.data.createAsset({type: type}, id);
  print('created ' + type + ': ' + id);
};
[CONFIG.collection100, CONFIG.imageCollection].forEach(function (c) {
  ensureContainer(c, 'IMAGE_COLLECTION');
});

// ---------------------------- create the tasks ---------------------------------
var name100 = function (y) { return CONFIG.prefix100 + y + '_v' + CONFIG.version; };
var name30  = function (y) { return CONFIG.imagePrefix + y + '_v' + CONFIG.version; };

var createExports = function (active, have100, have30) {
  var skipped = [], waiting = [];
  var skip = function (name, why) { skipped.push(name + ' [' + why + ']'); };
  CONFIG.years.forEach(function (year) {
    var n1 = name100(year), id1 = CONFIG.collection100 + '/' + n1;
    var n2 = name30(year),  id2 = CONFIG.imageCollection + '/' + n2;
    var n3 = 'isolation_forest_col11_' + year;
    if (CONFIG.step === 1) {
      if (active[n1]) return skip(n1, active[n1]);
      if (have100[id1]) return skip(n1, 'asset exists');
      Export.image.toAsset({image: isolation100(year).set(props(year, CONFIG.workScale)),
        description: n1, assetId: id1, region: geometry, crs: CONFIG.workCrs,
        scale: CONFIG.workScale, pyramidingPolicy: {'.default': 'mode'}, maxPixels: 1e13});
      return;
    }
    if (!have100[id1]) { waiting.push(year); return; }      // step 1 not finished yet
    var img100 = ee.Image(id1);
    if (CONFIG.step === 2) {
      if (active[n2]) return skip(n2, active[n2]);
      if (have30[id2]) return skip(n2, 'asset exists');
      Export.image.toAsset({image: isolation30(img100, year).set(props(year, 30)),
        description: n2, assetId: id2, region: geometry, crs: 'EPSG:4326', scale: 30,
        pyramidingPolicy: {'.default': 'mode'}, maxPixels: 1e13});
    } else if (CONFIG.step === 3) {
      if (active[n3]) return skip(n3, active[n3]);
      // uses the stored 30 m map when it exists (cheapest), otherwise derives it on the fly
      var img30 = have30[id2] ? ee.Image(id2) : isolation30(img100, year);
      Export.table.toDrive({collection: tableYear(img30, year), description: n3,
        folder: CONFIG.driveFolder, fileFormat: 'CSV',
        selectors: ['year', 'territory', 'source_ha', 'target_ha', 'dist_class', 'area_ha']});
    }
  });
  print('STEP ' + CONFIG.step + ': skipped ' + skipped.length + ' (running or done):', skipped);
  if (waiting.length) print('STEP ' + CONFIG.step + ': waiting for STEP 1 (100 m) of years:', waiting);
};

// async checks (the editor never freezes): recent tasks + both ImageCollections
var pending = 3, active = {}, have100 = {}, have30 = {};
var done = function () { if (--pending === 0) createExports(active, have100, have30); };
var ACTIVE = ['PENDING', 'READY', 'RUNNING', 'CANCEL_REQUESTED', 'CANCELLING'];
if (CONFIG.skipCheck) {
  ee.data.listOperations(CONFIG.recentTasks, function (ops, err) {
    if (err) print('Task list unavailable (no skipping by name):', err);
    (ops || []).forEach(function (op) {
      var m = op.metadata || {};
      if (m.description && ACTIVE.indexOf(m.state) >= 0) active[m.description] = m.state;
    });
    done();
  });
} else { done(); }
var listInto = function (coll, dict) {
  ee.data.listAssets(coll, {}, function (res, err) {
    ((res && res.assets) || []).forEach(function (a) { dict[a.id] = true; dict[a.name] = true; });
    done();
  });
};
listInto(CONFIG.collection100, have100);
listInto(CONFIG.imageCollection, have30);
