"""This is a Snakemake file defining rules to retrieve raw data from online sources."""
import pycountry

PYTHON = "PYTHONPATH=./ python"
PYTHON_SCRIPT = "PYTHONPATH=./ python {input} {output}"
PYTHON_SCRIPT_WITH_CONFIG = PYTHON_SCRIPT + " {CONFIG_FILE}"

URL_LOAD = "https://data.open-power-system-data.org/time_series/2017-07-09/time_series_60min_stacked.csv"
URL_REGIONS = "http://ec.europa.eu/eurostat/cache/GISCO/geodatafiles/NUTS_2013_01M_SH.zip"
URL_LAND_COVER = "http://due.esrin.esa.int/files/Globcover2009_V2.3_Global_.zip"
URL_PROTECTED_AREAS = "https://www.protectedplanet.net/downloads/WDPA_Jan2018?type=shapefile"
URL_CGIAR_TILE = "http://droppr.org/srtm/v4.1/6_5x5_TIFs/"
URL_GMTED_TILE = "https://edcintl.cr.usgs.gov/downloads/sciweb1/shared/topo/downloads/GMTED/Global_tiles_GMTED/075darcsec/mea/"
URL_GADM = "http://biogeo.ucdavis.edu/data/gadm2.8/gpkg"

RESOLUTION_STUDY = (1 / 3600) * 10 # 10 arcseconds
RESOLUTION_SLOPE = (1 / 3600) * 3 # 3 arcseconds

CRS_STUDY = "EPSG:4326"

SRTM_X_MIN = 34 # x coordinate of CGIAR tile raster
SRTM_X_MAX = 44
SRTM_Y_MIN = 1 # y coordinate of CGIAR tile raster
SRTM_Y_MAX = 8
GMTED_Y = ["50N", "70N"]
GMTED_X = ["030W", "000E", "030E"]


rule raw_load:
    message: "Download raw load."
    output:
        protected("build/raw-load-data.csv")
    shell:
        "curl -Lo {output} '{URL_LOAD}'"


rule electricity_demand_national:
    message: "Determine yearly demand per country."
    input:
        "src/process_load.py",
        rules.raw_load.output
    output:
        temp("build/electricity-demand-national.csv")
    shell:
        PYTHON_SCRIPT_WITH_CONFIG


rule raw_administrative_borders_zipped:
    message: "Download administrative borders for {wildcards.country_code} as zip."
    output: protected("build/raw-gadm/{country_code}.zip")
    shell: "curl -Lo {output} '{URL_GADM}/{wildcards.country_code}_adm_gpkg.zip'"


rule raw_administrative_borders:
    message: "Unzip administrative borders of {wildcards.country_code} as zip."
    input: "build/raw-gadm/{country_code}.zip"
    output: temp("build/raw-gadm/{country_code}_adm.gpkg")
    shell: "unzip -o {input} -d build/raw-gadm"


rule administrative_borders:
    message: "Merge administrative borders of all countries up to layer {params.max_layer_depth}."
    input:
        "src/administrative_borders.py",
        ["build/raw-gadm/{}_adm.gpkg".format(country_code)
            for country_code in [pycountry.countries.lookup(country).alpha_3
                                 for country in config['scope']['countries']]
         ]
    params: max_layer_depth = 3
    output: "build/administrative-borders.gpkg"
    shell:
        PYTHON + " {input} {params.max_layer_depth} {output}"

rule raw_regions_zipped:
    message: "Download regions as zip."
    output:
        protected("build/raw-regions.zip")
    shell:
        "curl -Lo {output} '{URL_REGIONS}'"


rule raw_regions:
    message: "Extract regions as zip."
    input: rules.raw_regions_zipped.output
    output: "build/NUTS_2013_01M_SH/data/NUTS_RG_01M_2013.shp"
    shell:
        "unzip {input} -d ./build"


rule raw_land_cover_zipped:
    message: "Download land cover data as zip."
    output: protected("build/raw-globcover2009.zip")
    shell: "curl -Lo {output} '{URL_LAND_COVER}'"


rule raw_land_cover:
    message: "Extract land cover data as zip."
    input: rules.raw_land_cover_zipped.output
    output: "build/raw-globcover2009-v2.3/GLOBCOVER_L4_200901_200912_V2.3.tif"
    shell: "unzip {input} -d ./build/raw-globcover2009-v2.3"


rule raw_protected_areas_zipped:
    message: "Download protected areas data as zip."
    output: protected("build/raw-wdpa.zip")
    shell: "curl -Lo {output} -H 'Referer: {URL_PROTECTED_AREAS}' {URL_PROTECTED_AREAS}"


rule raw_protected_areas:
    message: "Extract protected areas data as zip."
    input: rules.raw_protected_areas_zipped.output
    output:
        polygons = "build/raw-wdpa-jan2018/WDPA_Jan2018-shapefile-polygons.shp",
        points = "build/raw-wdpa-jan2018/WDPA_Jan2018-shapefile-points.shp"
    shell: "unzip {input} -d build/raw-wdpa-jan2018"


rule raw_srtm_elevation_tile:
    message: "Download SRTM elevation data tile (x={wildcards.x}, y={wildcards.y}) from CGIAR."
    output:
        tif = temp("build/srtm_{x}_{y}.tif"),
        zip = temp("build/srtm_{x}_{y}.zip")
    shadow: "full"
    threads: config["snakemake"]["max-threads"] # hack to prevent parallel execution which fails
    shell:
        """
        curl -Lo {output.zip} '{URL_CGIAR_TILE}/srtm_{wildcards.x}_{wildcards.y}.zip'
        unzip {output.zip} -d build
        """


rule raw_srtm_elevation_data:
    message: "Merge all SRTM elevation data tiles."
    input:
        ["build/srtm_{x:02d}_{y:02d}.tif".format(x=x, y=y)
         for x in range(SRTM_X_MIN, SRTM_X_MAX + 1)
         for y in range(SRTM_Y_MIN, SRTM_Y_MAX + 1)
         if not (x is 34 and y in [3, 4, 5, 6])] # these tiles do not exist
    output:
        protected("build/raw-srtm-elevation-data.tif")
    shell:
        "rio merge {input} {output} --force-overwrite"


rule raw_gmted_elevation_tile:
    message: "Download GMTED elevation data tile."
    output:
        temp("build/raw-gmted-{y}-{x}.tif")
    run:
        url = "{base_url}/{x_inverse}/{y}{x}_20101117_gmted_mea075.tif".format(**{
            "base_url": URL_GMTED_TILE,
            "x": wildcards.x,
            "y": wildcards.y,
            "x_inverse": wildcards.x[-1] + wildcards.x[:-1]
        })
        shell("curl -Lo {output} '{url}'".format(**{"url": url, "output": output}))


rule raw_gmted_elevation_data:
    message: "Merge all GMTED elevation data tiles."
    input:
        ["build/raw-gmted-{y}-{x}.tif".format(x=x, y=y)
         for x in GMTED_X
         for y in GMTED_Y
         ]
    output:
        protected("build/raw-gmted-elevation-data.tif")
    shell:
        "rio merge {input} {output} --force-overwrite"


rule elevation_in_europe:
    message: "Merge SRTM and GMTED elevation data and warp/clip to Europe using {threads} threads."
    input:
        gmted = rules.raw_gmted_elevation_data.output,
        srtm = rules.raw_srtm_elevation_data.output
    output:
        "build/elevation-europe.tif"
    params:
        srtm_bounds = "{x_min} {y_min} {x_max} 60".format(**config["scope"]["bounds"]),
        gmted_bounds = "{x_min} 59.5 {x_max} {y_max}".format(**config["scope"]["bounds"])
    threads: config["snakemake"]["max-threads"]
    shell:
        """
        rio clip --bounds {params.srtm_bounds} {input.srtm} -o build/tmp-srtm.tif
        rio clip --bounds {params.gmted_bounds} {input.gmted} -o build/tmp-gmted.tif
        rio warp build/tmp-gmted.tif -o build/tmp-gmted2.tif -r {RESOLUTION_SLOPE} \
        --resampling nearest --threads {threads}
        rio merge build/tmp-srtm.tif build/tmp-gmted2.tif {output}
        rm build/tmp-gmted.tif
        rm build/tmp-gmted2.tif
        rm build/tmp-srtm.tif
        """

rule land_cover_in_europe:
    message: "Clip land cover data to Europe."
    input: rules.raw_land_cover.output
    output: "build/land-cover-europe.tif"
    params: bounds = "{x_min} {y_min} {x_max} {y_max}".format(**config["scope"]["bounds"])
    shell: "rio clip {input} {output} --bounds {params.bounds}"


rule slope_in_europe:
    message: "Calculate slope and warp to resolution of study using {threads} threads."
    input:
        elevation = rules.elevation_in_europe.output,
        land_cover = rules.land_cover_in_europe.output
    output:
        "build/slope-europe.tif"
    threads: config["snakemake"]["max-threads"]
    shell:
        """
        gdaldem slope -s 111120 -compute_edges {input.elevation} build/slope-temp.tif
        rio warp build/slope-temp.tif -o {output} --like {input.land_cover} \
        --resampling max --threads {threads}
        rm build/slope-temp.tif
        """


rule protected_areas_points_to_circles:
    message: "Estimate shape of protected areas available as points only."
    input:
        "src/estimate_protected_shapes.py",
        rules.raw_protected_areas.output.points
    output:
        temp("build/protected-areas-points-as-circles.geojson")
    shell:
        PYTHON_SCRIPT_WITH_CONFIG


rule protected_areas_in_europe:
    message: "Rasterise protected areas data and clip to Europe."
    input:
        polygons = rules.raw_protected_areas.output.polygons,
        points = rules.protected_areas_points_to_circles.output,
        land_cover = rules.land_cover_in_europe.output
    output:
        "build/protected-areas-europe.tif"
    benchmark:
        "build/rasterisation-benchmark.txt"
    shell:
        # fio cat below should use a bounding box to not forward polygons outside
        # the study area. This would increase the performance drastically. Doing so
        # is blocked by bug https://github.com/Toblerity/Fiona/issues/543
        """
        fio cat --rs {input.points} {input.polygons} | \
        fio filter "f.properties.STATUS == 'Designated'" | \
        fio collect --record-buffered | \
        rio rasterize --like {input.land_cover} \
        --default-value 255 --all_touched -f "GTiff" --co dtype=uint8 -o {output}
        """
