#!/bin/sh

wait_for_server () {

    server_host=$1
    server_port=$2
    sleep_seconds=5

    while true; do
        echo -n "Checking $server_host $server_port status... "

        nc -z "$server_host" "$server_port"

        if [ "$?" -eq 0 ]; then
            echo "$server_host is running and ready to process requests."
            break
        fi

        echo "$server_host is warming up. Trying again in $sleep_seconds seconds..."
        sleep $sleep_seconds
    done
}

chmod 755 /opt

if ! hash curl > /dev/null 2>&1 || ! hash gosu > /dev/null 2>&1 || ! hash nc > /dev/null 2>&1 || ! hash psql > /dev/null 2>&1 ; then
    apt update && apt install -y gosu curl netcat postgresql-client
fi

if ! id osrm > /dev/null 2>&1 ; then
    useradd --create-home osrm &> /dev/null
fi

if ! id postgres > /dev/null 2>&1 ; then
    useradd --create-home postgres &> /dev/null
fi

if ! id osm > /dev/null 2>&1 ; then
    useradd --create-home osm &> /dev/null
fi

if [ -f /usr/local/etc/osm-config.sh ]; then
    . /usr/local/etc/osm-config.sh
fi

: ${PROFILE:=/opt/car.lua}
: ${PROFILE_DIR:=$(basename "$PROFILE" .lua)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
export PROFILE PROFILE_DIR OSM_OSRM

# mainly so 2 containers aren't trying to download the pbf at the same time.
wait_for_server renderd 7653

if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
    gosu osrm curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
    gosu osrm curl -L -z /data/"$OSM_PBF".md5 -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
    cd /data && \
        gosu osrm md5sum -c "$OSM_PBF".md5 || exit 1
fi

# detect if binaries are a different version to the ones used to process the previous osm files,
# and reprocess if they are different.
if [ -f /data/osrm.version ]; then
    if [ "`osrm-extract -v`" != "`cat /data/osrm.version`" ]; then
        REEXTRACT=1
    fi
else
    REEXTRACT=1
fi

if [ "$REDOWNLOAD" -o "$REEXTRACT" -o ! -f /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" ]; then
    if [ ! -d /data/"$PROFILE_DIR" ]; then
        gosu osrm mkdir -p /data/profile/"$PROFILE_DIR"
    fi
    gosu osrm osrm-extract -p "$PROFILE" /data/"$OSM_PBF" && \
        gosu osrm osrm-partition /data/"$OSM_OSRM" && \
        gosu osrm osrm-customize /data/"$OSM_OSRM" && \
        mv /data/"$OSM_OSRM"* /data/profile/"$PROFILE_DIR" && \
        osrm-extract -v > /data/osrm.version
fi

cd /

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

exec gosu osrm osrm-routed -t "$NPROCS" --algorithm mld /data/profile/"$PROFILE_DIR"/"$OSM_OSRM"

