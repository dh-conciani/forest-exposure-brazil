// calc edge area
var classificationInput = ee.Image('projects/mapbiomas-workspace/DEGRADACAO/COLECAO/BETA/PROCESS/summary/patch_col9_v1').aside(print)

// define classification regions 
var territory = ee.Image('projects/mapbiomas-territories/assets/TERRITORIES/LULC/BRAZIL/COLLECTION9/WORKSPACE/INFORMACAO_AMBIENTAL_VEGETACAO_IBGE_raster')
        .rename('territory');

// plot regions
Map.addLayer(territory.randomVisualizer());

// set collection
var col = ee.Image('projects/mapbiomas-public/assets/brazil/lulc/collection9/mapbiomas_collection90_integration_v1');


// change the scale if you need.
var scale = 30;

// define the years to bem computed 
var years = ee.List.sequence({'start': 1985, 'end': 2023, 'step': 1}).getInfo();

// define a Google Drive output folder 
var driverFolder = 'AREA-PAPER-DEGRAD';

  // get the classification for the file[i] 
  var asset_i = classificationInput;
  // set only the basename
  var basename = 'area_patch_ibge_c9'
  
  // Image area in km2
  var pixelArea = ee.Image.pixelArea().divide(10000);
  
  // Geometry to export
  var geometry = territory.geometry();
  
  // convert a complex object to a simple feature collection 
  var convert2table = function (obj) {
    obj = ee.Dictionary(obj);
      var territory = obj.get('territory');
      var classesAndAreas = ee.List(obj.get('groups'));
      
      var tableRows = classesAndAreas.map(
          function (classAndArea) {
              classAndArea = ee.Dictionary(classAndArea);
              var classId = classAndArea.get('class');
              var area = classAndArea.get('sum');
              var tableColumns = ee.Feature(null)
                  .set('territory', territory)
                  .set('class_id', classId)
                  .set('area', area)
                  .set('file', basename);
                  
              return tableColumns;
          }
      );
  
      return ee.FeatureCollection(ee.List(tableRows));
  };
  
  // compute the area
  var calculateArea = function (image, territory, geometry) {
      var territotiesData = pixelArea.addBands(territory).addBands(image)
          .reduceRegion({
              reducer: ee.Reducer.sum().group(1, 'class').group(1, 'territory'),
              geometry: geometry,
              scale: scale,
              maxPixels: 1e12
          });
          
      territotiesData = ee.List(territotiesData.get('groups'));
      var areas = territotiesData.map(convert2table);
      areas = ee.FeatureCollection(areas).flatten();
      return areas;
  };
  
  // perform per year 
  var areas = years.map(
      function (year) {
          // build forest mask
          var col_i = col.select('classification_' + year)
            .remap({'from': [3, 5, 6, 49],
                    'to': [1, 1, 1, 1],
                    'defaultValue': 0}).selfMask()
        
        // apply mask
          var image = asset_i.select('patch_' + year).updateMask(col_i);
          Map.addLayer(image.randomVisualizer(), {}, String(year), false)
          
          var areas = calculateArea(image, territory, geometry);
          // set additional properties
          areas = areas.map(
              function (feature) {
                  return feature.set('year', year);
              }
          );
          return areas;
      }
  );
  
  areas = ee.FeatureCollection(areas).flatten();
  
  Export.table.toDrive({
      collection: areas,
      description: basename,
      folder: driverFolder,
      fileFormat: 'CSV'
  });