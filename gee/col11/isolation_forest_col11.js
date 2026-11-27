/* =============================================================================
 * isolation_forest_col11.js
 * Habitat isolation of FOREST for the paper, on the MapBiomas Collection 11
 * degradation inputs, exported as area tables ready for the R pipeline.
 *
 * Same conceptual rule as the Degradation Module ATBD v2, section 2.6:
 *   a forest pixel is "isolated" when it belongs to a TARGET native-vegetation
 *   patch (<= 25 / 50 / 100 ha) whose nearest SOURCE patch (>= 100 / 500 / 1000 ha)
 *   is >= 5 / 10 / 20 km away.
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
 * HOW TO RUN
 *   - Fill the CONFIG block (asset ids marked TODO).
 *   - Run: one Export.table task per year is created (39 tasks, 1986-2024).
 *     Start them from the Tasks tab (or with the "Run all" helper of your choice).
 *   - Download the CSVs into data/raw/col11/isolation/ and run
 *     scripts/01_prepare_exposure.R with COLLECTION = "col11".
 *
 * Output columns: year, territory (biome*100 + LULC class), source_ha, target_ha,
 *                 dist_class (0 = reference forest area; 5 = 5-10 km; 10 = 10-20 km;
 *                 20 = >= 20 km; EXCLUSIVE classes), area_ha
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
  distances:   [5000, 10000, 20000],  // m; EXACTLY 3 values (dist_class 5 / 10 / 20 below)
  forestClasses: [3, 5, 6, 49],       // forest formation, mangrove, floodable forest, wooded sandbank
  workScale: 100,                     // m, scale of distance computation
  workCrs: 'EPSG:5880',               // SIRGAS 2000 / Brazil Polyconic (metric)
  driveFolder: 'PAPER-DEGRAD-COL11',
  exportIsolationImages: false        // true -> also export yearly 30 m isolation asset (Figure 2)
};

var lulc      = ee.Image(CONFIG.lulc);
// patch size (ha) of one year: the asset is an ImageCollection, not a multiband image
var patchSizeOf = function (year) {
  return ee.Image(CONFIG.patchSize + '/' + CONFIG.patchPrefix + year + CONFIG.patchSuffix)
    .select(0).rename('size');
};
if (CONFIG.distances.length !== 3) {
  throw new Error('CONFIG.distances must have exactly 3 values (5/10/20 km classes).');
}
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

var processYear = function (year) {
  var size = patchSizeOf(year);               // native patch size, ha
  var lulcY = lulc.select('classification_' + year);
  var forest = lulcY.remap(CONFIG.forestClasses,
                           ee.List.repeat(1, CONFIG.forestClasses.length), 0).selfMask();
  // territory code = biome id * 100 + LULC class (lets R keep forest classes apart)
  var territory = biomes.multiply(100).add(lulcY).rename('territory');

  // distances to each source size, computed once
  var dist = {};
  CONFIG.sourceSizes.forEach(function (s) {
    dist[s] = distanceFrom(to100(size.gte(s).selfMask()));
  });

  var rows = ee.FeatureCollection([]);

  // reference forest area (dist_class 0)
  var refStats = pixelArea.updateMask(forest).addBands(territory)
    .reduceRegion({reducer: ee.Reducer.sum().group(1, 'territory'),
                   geometry: geometry, scale: 30, maxPixels: 1e13, tileScale: 4});
  rows = rows.merge(ee.FeatureCollection(ee.List(refStats.get('groups')).map(function (g) {
    g = ee.Dictionary(g);
    return ee.Feature(null, {year: year, territory: g.get('territory'), source_ha: 0,
                             target_ha: 0, dist_class: 0, area_ha: g.get('sum')});
  })));

  CONFIG.targetSizes.forEach(function (t) {
    var target30 = size.lte(t).selfMask();
    // connected target patches at 100 m (8-neighbour) and their labels
    var target100 = to100(target30).selfMask();
    var labels = target100.connectedComponents(ee.Kernel.square(1), 256).select('labels');

    CONFIG.sourceSizes.forEach(function (s) {
      // minimum distance over each target patch
      var minDist = dist[s].addBands(labels)
        .reduceConnectedComponents(ee.Reducer.min(), 'labels', 256)
        .reproject(proj100);
      // exclusive distance class at 100 m
      var cls100 = ee.Image(0)
        .where(minDist.gte(CONFIG.distances[0]), 5)
        .where(minDist.gte(CONFIG.distances[1]), 10)
        .where(minDist.gte(CONFIG.distances[2]), 20)
        .reproject(proj100).selfMask();
      // back to 30 m: forest pixels of target patches inside isolated cells
      var cls30 = cls100.updateMask(target30).updateMask(forest).rename('dist_class');

      if (CONFIG.exportIsolationImages && s === 1000 && t === 100) {
        Export.image.toAsset({image: cls30.toByte(), description: 'isol_forest_s1000_t100_' + year,
          assetId: 'users/TODO/isol_forest_s1000_t100_' + year, region: geometry,
          scale: 30, maxPixels: 1e13});
      }

      var st = pixelArea.updateMask(cls30).addBands(cls30).addBands(territory)
        .reduceRegion({reducer: ee.Reducer.sum().group(1, 'dist_class').group(2, 'territory'),
                       geometry: geometry, scale: 30, maxPixels: 1e13, tileScale: 4});
      var feats = ee.List(st.get('groups')).map(function (g) {
        g = ee.Dictionary(g);
        var terr = g.get('territory');
        return ee.List(g.get('groups')).map(function (h) {
          h = ee.Dictionary(h);
          return ee.Feature(null, {year: year, territory: terr, source_ha: s, target_ha: t,
                                   dist_class: h.get('dist_class'), area_ha: h.get('sum')});
        });
      }).flatten();
      rows = rows.merge(ee.FeatureCollection(feats));
    });
  });
  return rows;
};

CONFIG.years.forEach(function (year) {
  Export.table.toDrive({
    collection: processYear(year),
    description: 'isolation_forest_col11_' + year,
    folder: CONFIG.driveFolder,
    fileFormat: 'CSV',
    selectors: ['year', 'territory', 'source_ha', 'target_ha', 'dist_class', 'area_ha']
  });
});

// Quick visual check for one year (no export)
var y = 2022;
Map.addLayer(patchSizeOf(y).lte(100).selfMask(), {palette: ['orange']}, 'targets <= 100 ha ' + y, false);
Map.addLayer(patchSizeOf(y).gte(1000).selfMask(), {palette: ['darkgreen']}, 'sources >= 1000 ha ' + y, false);
