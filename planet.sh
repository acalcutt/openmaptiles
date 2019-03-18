#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset


###########################################
# OpenMapTiles quickstart.sh for x86_64 linux
#
# Example calls ...
# ./quickstart.sh
# ./quickstart.sh africa
# ./quickstart.sh alabama
# ./quickstart.sh alaska
# ./quickstart.sh albania
# ./quickstart.sh alberta
# ./quickstart.sh alps
# ....
#
# to list areas :  make download-geofabrik-list
# see more QUICKSTART.md
#

osm_area=planet
PBF=planet-latest.osm.pbf
PBF_BASE=http://planet.osm.org/pbf/

AREA=Planet
PBF=planet-latest.osm.pbf
PBF_BASE=http://planet.osm.org/pbf/
DOCKER_COMPOSE_FILE=docker-compose-config.yml
MIN_ZOOM=0
MAX_ZOOM=16


##  Min versions ...
MIN_COMPOSE_VER=1.7.1
MIN_DOCKER_VER=1.12.3
STARTTIME=$(date +%s)
STARTDATE=$(date +"%Y-%m-%dT%H:%M%z")
githash=$( git rev-parse HEAD )

log_file=./planet.log
rm -f $log_file
echo " "
echo "====================================================================================="
echo "                       Docker check & Download images                                "
echo "-------------------------------------------------------------------------------------"
echo "====> : Please check the Docker and docker-compose version!"
echo "      : We are using docker-compose v2 file format!  see more at https://docs.docker.com/"
echo "      : Minimum required Docker version: $MIN_DOCKER_VER+"
echo "      : Minimum required docker-compose version: $MIN_COMPOSE_VER+"
echo "      : See the .travis build for the currently supported versions."
echo "      : Your docker system:"
docker         --version
docker-compose --version

# based on: http://stackoverflow.com/questions/16989598/bash-comparing-version-numbers
function version { echo "$@" | tr -cs '0-9.' '.' | gawk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }'; }

COMPOSE_VER=$(docker-compose version --short)
if [ "$(version "$COMPOSE_VER")" -lt "$(version "$MIN_COMPOSE_VER")" ]; then
  echo "ERR: Your Docker-compose version is Known to have bugs , Please Update docker-compose!"
  exit 1
fi

DOCKER_VER="$(docker -v | awk -F '[ ,]+' '{ print $3 }')"
if [ "$(version "$DOCKER_VER")" -lt "$(version "$MIN_DOCKER_VER")" ]; then
  echo "ERR: Your Docker version is not compatible. Please Update docker!"
  exit 1
fi

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Pulling or refreshing OpenMapTiles docker images "
make refresh-docker-images


#####  backup log from here ...
exec &> >(tee -a "$log_file")

echo " "
echo "====================================================================================="
echo "                                Start processing                                     "
echo "-------------------------------------------------------------------------------------"
echo "====> : OpenMapTiles quickstart! [ https://github.com/openmaptiles/openmaptiles ]    "
echo "      : This will be logged to the $log_file file (for debugging) and to the screen"
echo "      : Area             : $AREA "
echo "      : Git version      : $githash "
echo "      : Started          : $STARTDATE "
echo "      : Your bash version: $BASH_VERSION"
echo "      : Your OS          : $OSTYPE"
docker         --version
docker-compose --version

if [[ "$OSTYPE" == "linux-gnu" ]]; then
    echo " "
    echo "-------------------------------------------------------------------------------------"
    echo "      : This is working on x86_64 ; Your kernel is:"
    uname -r
    uname -m

    KERNEL_CPU_VER=$(uname -m)
    if [ "$KERNEL_CPU_VER" != "x86_64" ]; then
      echo "ERR: Sorry this is working only on x86_64!"
      exit 1
    fi
    echo "      : --- Memory, CPU info ---- "
    mem=$( grep MemTotal /proc/meminfo | awk '{print $2}' | xargs -I {} echo "scale=4; {}/1024^2" | bc  )
    echo "system memory (GB): ${mem}  "
    grep SwapTotal /proc/meminfo
    echo cpu number: $(grep -c processor /proc/cpuinfo) x $(cat /proc/cpuinfo | grep "bogomips" | head -1)
    cat /proc/meminfo  | grep Free
else
    echo " "
    echo "Warning : Platforms other than Linux are less tested"
    echo " "
fi

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Stopping running services & removing old containers"
make clean-docker

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Checking OpenMapTiles docker images "
docker images | grep openmaptiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Making directories - if they don't exist ( ./build ./data ./pgdata ) "
mkdir -p pgdata
mkdir -p build
mkdir -p data
mkdir -p wikidata

echo " "
echo "-------------------------------------------------------------------------------------"

echo "====> : Downloading PBF $PBF"
if [ ! -f data/$PBF ]; then
	wget $PBF_BASE$PBF -P data
	ls data/*.osm.pbf  -la
fi

echo "====> : Creating Docker Compose File $DOCKER_COMPOSE_FILE"
if [ ! -f data/$PBF ]; then
    echo " "
    echo "Missing ./data/$PBF , Download or Parameter error? "
    exit 404
else
	if [ ! -f data/$DOCKER_COMPOSE_FILE ]; then
		
		rm -f data/*.txt
		rm -f data/*.yml

		osmconvert  --out-statistics  data/$PBF  > data/osmstat.txt

		lon_min=$( cat data/osmstat.txt | grep "lon min:" |cut -d":" -f 2 )
		lon_max=$( cat data/osmstat.txt | grep "lon max:" |cut -d":" -f 2 )
		lat_min=$( cat data/osmstat.txt | grep "lat min:" |cut -d":" -f 2 )
		lat_max=$( cat data/osmstat.txt | grep "lat max:" |cut -d":" -f 2 )
		timestamp_max=$( cat data/osmstat.txt | grep "timestamp max:" |cut -d" " -f 3 )
		
		echo "====> : Osm metadata : $PBF   "
		cat data/osmstat.txt

		echo "--------------------------------------------"
		echo BBOX: "$lon_min,$lat_min,$lon_max,$lat_max"
		echo TIMESTAMP MAX = $timestamp_max
		echo MIN_ZOOM: "$MIN_ZOOM"
		echo MAX_ZOOM: "$MAX_ZOOM"
		echo "--------------------------------------------"

		cat > data/$DOCKER_COMPOSE_FILE  <<- EOM
		version: "2"
		services:
		  generate-vectortiles:
		    environment:
		      BBOX: "$lon_min,$lat_min,$lon_max,$lat_max"
		      OSM_MAX_TIMESTAMP : "$timestamp_max"
		      OSM_AREA_NAME: "$AREA"
		      MIN_ZOOM: "$MIN_ZOOM"
		      MAX_ZOOM: "$MAX_ZOOM"
		EOM
	fi
fi

rm -f ./data/*.mbtiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Remove old generated source files ( ./build/* ) ( if they exist ) "
docker-compose run --rm openmaptiles-tools make clean

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Code generating from the layer definitions ( ./build/mapping.yaml; ./build/tileset.sql )"
echo "      : The tool source code: https://github.com/openmaptiles/openmaptiles-tools "
echo "      : But we generate the tm2source, Imposm mappings and SQL functions from the layer definitions! "
docker-compose run --rm openmaptiles-tools make

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start PostgreSQL service ; create PostgreSQL data volume "
echo "      : Source code: https://github.com/openmaptiles/postgis "
echo "      : Thank you: https://www.postgresql.org !  Thank you http://postgis.org !"
docker-compose up   -d postgres

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Drop and Recreate PostgreSQL  public schema "
# Drop all PostgreSQL tables
# This adds an extra safety belt if the user modifies the docker volume settings
make forced-clean-sql

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing water data from http://openstreetmapdata.com into PostgreSQL "
echo "      : Source code:  https://github.com/openmaptiles/import-water "
echo "      : Data license: http://openstreetmapdata.com/info/license  "
echo "      : Thank you: http://openstreetmapdata.com/info/supporting "
docker-compose run --rm import-water

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing border data from http://openstreetmap.org into PostgreSQL "
echo "      : Source code:  https://github.com/openmaptiles/import-osmborder"
echo "      : Data license: http://www.openstreetmap.org/copyright"
echo "      : Thank you: https://github.com/pnorman/osmborder "
docker-compose run --rm import-osmborder

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing  http://www.naturalearthdata.com  into PostgreSQL "
echo "      : Source code: https://github.com/openmaptiles/import-natural-earth "
echo "      : Terms-of-use: http://www.naturalearthdata.com/about/terms-of-use  "
echo "      : Thank you: Natural Earth Contributors! "
docker-compose run --rm import-natural-earth

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing OpenStreetMap Lakelines data "
echo "      : Source code: https://github.com/openmaptiles/import-lakelines "
echo "      :              https://github.com/lukasmartinelli/osm-lakelines "
echo "      : Data license: .. "
docker-compose run --rm import-lakelines

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing OpenStreetMap data: ./data/${PBF} -> imposm3[./build/mapping.yaml] -> PostgreSQL"
echo "      : Imposm3 documentation: https://imposm.org/docs/imposm3/latest/index.html "
echo "      :   Thank you Omniscale! "
echo "      :   Source code: https://github.com/openmaptiles/import-osm "
echo "      : The OpenstreetMap data license: https://www.openstreetmap.org/copyright (ODBL) "
echo "      : Thank you OpenStreetMap Contributors ! "
docker-compose run --rm import-osm

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start importing Wikidata: ./wikidata/latest-all.json.gz -> PostgreSQL"
echo "      : Source code: https://github.com/openmaptiles/import-wikidata "
echo "      : The Wikidata license: https://www.wikidata.org/wiki/Wikidata:Database_download/en#License "
echo "      : Thank you Wikidata Contributors ! "
docker-compose run --rm import-wikidata

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start SQL postprocessing:  ./build/tileset.sql -> PostgreSQL "
echo "      : Source code: https://github.com/openmaptiles/import-sql "
docker-compose run --rm import-sql

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Analyze PostgreSQL tables"
make psql-analyze

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Bring up postserve at localhost:8090/tiles/{z}/{x}/{y}.pbf"
docker-compose up -d postserve

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Start generating MBTiles (containing gzipped MVT PBF) from a TM2Source project. "
echo "      : TM2Source project definitions : ./build/openmaptiles.tm2source/data.yml "
echo "      : Output MBTiles: ./data/tiles.mbtiles  "
echo "      : Source code: https://github.com/openmaptiles/generate-vectortiles "
echo "      : We are using a lot of Mapbox Open Source tools! : https://github.com/mapbox "
echo "      : Thank you https://www.mapbox.com !"
echo "      : See other MVT tools : https://github.com/mapbox/awesome-vector-tiles "
echo "      :  "
echo "      : You will see a lot of deprecated warning in the log! This is normal!  "
echo "      :    like :  Mapnik LOG>  ... is deprecated and will be removed in Mapnik 4.x ... "

docker-compose -f docker-compose.yml -f ./data/docker-compose-config.yml  run --rm generate-vectortiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Add special metadata to mbtiles! "
docker-compose run --rm openmaptiles-tools  generate-metadata ./data/tiles.mbtiles
docker-compose run --rm openmaptiles-tools  chmod 666         ./data/tiles.mbtiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Stop PostgreSQL service ( but we keep PostgreSQL data volume for debugging )"
docker-compose stop postgres

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : Inputs - Outputs md5sum for debugging "
rm -f ./data/quickstart_checklist.chk
md5sum build/mapping.yaml                     >> ./data/quickstart_checklist.chk
md5sum build/tileset.sql                      >> ./data/quickstart_checklist.chk
md5sum build/openmaptiles.tm2source/data.yml  >> ./data/quickstart_checklist.chk
md5sum ./data/${PBF}                     >> ./data/quickstart_checklist.chk
md5sum ./data/tiles.mbtiles                   >> ./data/quickstart_checklist.chk
md5sum ./data/docker-compose-config.yml       >> ./data/quickstart_checklist.chk
md5sum ./data/osmstat.txt                     >> ./data/quickstart_checklist.chk
cat ./data/quickstart_checklist.chk

ENDTIME=$(date +%s)
ENDDATE=$(date +"%Y-%m-%dT%H:%M%z")
if stat --help >/dev/null 2>&1; then
  MODDATE=$(stat -c %y ./data/${PBF} )
else
  MODDATE=$(stat -f%Sm -t '%F %T %z' ./data/${PBF} )
fi

echo " "
echo " "
echo "-------------------------------------------------------------------------------------"
echo "--                           S u m m a r y                                         --"
echo "-------------------------------------------------------------------------------------"
echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : (disk space) We have created a lot of docker images: "
echo "      : Hint: you can remove with:  docker rmi IMAGE "
docker images | grep openmaptiles


echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : (disk space) We have created this new docker volume for PostgreSQL data:"
echo "      : Hint: you can remove with : docker volume rm openmaptiles_pgdata "
docker volume ls -q | grep openmaptiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "====> : (disk space) We have created the new vectortiles ( ./data/tiles.mbtiles ) "
echo "      : Please respect the licenses (OdBL for OSM data) of the sources when distributing the MBTiles file."
echo "      : Created from $PBF ( file moddate: $MODDATE ) "
echo "      : Size: "
ls -la ./data/*.mbtiles

echo " "
echo "-------------------------------------------------------------------------------------"
echo "The ./quickstart.sh $AREA  is finished! "
echo "It takes $(($ENDTIME - $STARTTIME)) seconds to complete"
echo "We saved the log file to $log_file  ( for debugging ) You can compare with the travis log !"
echo " "
echo "Start experimenting! And check the QUICKSTART.MD file!"
echo "Available help commands (make help)  "
make help

echo "-------------------------------------------------------------------------------------"
echo " Acknowledgments "
echo " Generated vector tiles are produced work of OpenStreetMap data. "
echo " Such tiles are reusable under CC-BY license granted by OpenMapTiles team: "
echo "   https://github.com/openmaptiles/openmaptiles/#license "
echo " Maps made with these vector tiles must display a visible credit: "
echo "   © OpenMapTiles © OpenStreetMap contributors "
echo " "
echo " Thanks to all free, open source software developers and Open Data Contributors!    "
echo "-------------------------------------------------------------------------------------"
