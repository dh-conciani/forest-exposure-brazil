"""
Supplementary Fig. S1 — annual forest maps of Brazil, 1986–2024 (MapBiomas Collection 11).

One thumbnail per year (forest = classes 3, 5, 6 and 49, in green, over a light
background inside Brazil), with the biome boundaries in black, assembled into a
6-column panel with the year above each map.

Run (local or Colab):
    pip install earthengine-api pillow requests
    earthengine authenticate          # or ee.Authenticate() in Colab
    python figS1_forest_thumbnails.py --project <your-gee-cloud-project>

Output: figS1_forest_1986_2024.png (panel) and thumbs/forest_<year>.png.
"""
import argparse
import io
import os

import ee
import requests
from PIL import Image, ImageDraw, ImageFont

CONFIG = {
    "lulc": "projects/mapbiomas-public/assets/brazil/lulc/collection11/"
            "mapbiomas_brazil_collection11_coverage_v3",
    # raster of IBGE (2019) biomes, same asset used by the Col. 11 isolation script
    "biomes": "projects/mapbiomas-workspace/AUXILIAR/biomas-2019-raster_old",
    "forest_classes": [3, 5, 6, 49],
    "years": list(range(1986, 2025)),
    "forest_color": "1f8d49",
    "background_color": "e5f5e0",   # non-forest inside Brazil
    "border_color": "000000",
    "border_width_m": 2500,          # half-width of the biome lines
    "thumb_px": 600,                 # longest side of each thumbnail
    "ncols": 6,
}

# Brazil bounding box (lon/lat)
REGION = [-74.2, -34.0, -28.6, 5.5]


def build_image(year, biomes, border):
    lulc = ee.Image(CONFIG["lulc"]).select(f"classification_{year}")
    forest = lulc.remap(CONFIG["forest_classes"],
                        [1] * len(CONFIG["forest_classes"]), 0)
    brazil = biomes.gt(0)

    bg = brazil.selfMask().visualize(palette=[CONFIG["background_color"]])
    fg = forest.selfMask().visualize(palette=[CONFIG["forest_color"]])
    ln = border.selfMask().visualize(palette=[CONFIG["border_color"]])
    return ee.ImageCollection([bg, fg, ln]).mosaic()


def biome_borders(biomes):
    # a pixel is a border if the biome code changes within border_width_m
    r = CONFIG["border_width_m"]
    mx = biomes.unmask(0).focalMax(r, "circle", "meters")
    mn = biomes.unmask(0).focalMin(r, "circle", "meters")
    return mx.neq(mn).And(biomes.unmask(0).gt(0).Or(mx.gt(0)))


def fetch(img, path):
    url = img.getThumbURL({
        "region": ee.Geometry.Rectangle(REGION, None, False),
        "dimensions": CONFIG["thumb_px"],
        "format": "png",
        "crs": "EPSG:4326",
    })
    r = requests.get(url, timeout=300)
    r.raise_for_status()
    im = Image.open(io.BytesIO(r.content)).convert("RGBA")
    white = Image.new("RGBA", im.size, (255, 255, 255, 255))
    white.alpha_composite(im)
    white.convert("RGB").save(path)
    return path


def panel(paths, years, out):
    thumbs = [Image.open(p) for p in paths]
    w, h = thumbs[0].size
    label_h = int(h * 0.09)
    pad = int(w * 0.04)
    ncols = CONFIG["ncols"]
    nrows = -(-len(thumbs) // ncols)
    W = ncols * (w + pad) + pad
    H = nrows * (h + label_h + pad) + pad
    canvas = Image.new("RGB", (W, H), "white")
    draw = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", int(label_h * 0.6))
    except OSError:
        font = ImageFont.load_default()
    for i, (t, y) in enumerate(zip(thumbs, years)):
        c, r = i % ncols, i // ncols
        x0 = pad + c * (w + pad)
        y0 = pad + r * (h + label_h + pad)
        draw.rectangle([x0, y0, x0 + w, y0 + label_h], fill=(235, 235, 235))
        tw = draw.textlength(str(y), font=font)
        draw.text((x0 + (w - tw) / 2, y0 + label_h * 0.15), str(y),
                  fill="black", font=font)
        canvas.paste(t, (x0, y0 + label_h))
    canvas.save(out, dpi=(300, 300))
    print("saved", out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="GEE cloud project")
    ap.add_argument("--out", default="figS1_forest_1986_2024.png")
    a = ap.parse_args()

    ee.Initialize(project=a.project)
    os.makedirs("thumbs", exist_ok=True)
    biomes = ee.Image(CONFIG["biomes"]).selfMask()
    border = biome_borders(ee.Image(CONFIG["biomes"]))

    paths = []
    for y in CONFIG["years"]:
        p = f"thumbs/forest_{y}.png"
        if not os.path.exists(p):
            fetch(build_image(y, biomes, border), p)
            print("thumb", y)
        paths.append(p)
    panel(paths, CONFIG["years"], a.out)


if __name__ == "__main__":
    main()
