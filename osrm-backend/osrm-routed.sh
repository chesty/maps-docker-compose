#!/bin/sh

set -e

if [ -f /usr/local/etc/osm-config.sh ]; then
    . /usr/local/etc/osm-config.sh
else
    log () {
            echo `date "+%Y-%m-%d %H:%M:%S+%Z"` "-- $0: $@"
    }
    log "/usr/local/etc/osm-config.sh not found, $0 is probably going to error and exit"
fi

log starting

if ! hash curl > /dev/null 2>&1 || ! hash gosu > /dev/null 2>&1 || ! hash nc > /dev/null 2>&1 || ! hash psql > /dev/null 2>&1 ; then
    apt update && apt install -y gosu curl netcat postgresql-client
fi

: ${PROFILE:=/opt/car.lua}
: ${PROFILE_DIR:=$(basename "$PROFILE" .lua)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
export PROFILE PROFILE_DIR OSM_OSRM

log_env

check_lockfile /data/osrm-backend.lock "osrm-backend" || REDOWNLOAD=1

# mainly so 2 containers aren't trying to download the pbf at the same time.
wait_for_server renderd 7653

if [ "$REDOWNLOAD" -o ! -f "$DATA_DIR/$OSM_PBF" -o ! -f "$DATA_DIR/osmosis/state.txt" ]; then
    log "osrm-backend downloading $OSM_PBF_URL"
    gosu osm mkdir -p "$DATA_DIR/osmosis"
    gosu osm curl "$OSM_PBF_UPDATE_URL"/state.txt -o "$DATA_DIR/osmosis/state.txt" || {
        log "osrm-backend error downloading ${OSM_PBF_UPDATE_URL}/state.txt, exit 7"; exit 7; }
    gosu osm flock "$DATA_DIR/$OSM_PBF".lock curl --remote-time --location --retry 3 --time-cond "$DATA_DIR/$OSM_PBF" \
        --silent --show-error --output "$DATA_DIR/$OSM_PBF" "$OSM_PBF_URL" || {
        log "osrm-backend error downloading $OSM_PBF_URL, exit 8"; exit 8; }
    rm -f "$DATA_DIR/$OSM_PBF".lock
    gosu osm curl -L -o "$DATA_DIR/$OSM_PBF".md5 "$OSM_PBF_URL".md5 || {
        log "osrm-backend error downloading ${OSM_PBF_URL}.md5, exit 9"; exit 9; }
    ( cd "$DATA_DIR" && \
        gosu osm md5sum -c "$OSM_PBF".md5 ) || {
            rm -f "$DATA_DIR/$OSM_PBF".md5 "$DATA_DIR/$OSM_PBF"
            log "osrm-backend error md5sum mismatch on $DATA_DIR/$OSM_PBF, exit 4"
            exit 4
        }
fi

# detect if binaries are a different version to the ones used to process the previous osm files,
# and reprocess if they are different.
: ${OSRM_ALGORITHM:="MLD"}
FULLPATH_OSM_OSRM=/data/profile/"$PROFILE_DIR"/"$OSM_OSRM"
if [ -f "$FULLPATH_OSM_OSRM" ]; then
    if ! gosu osm osrm-routed --algorithm "$OSRM_ALGORITHM" --trial=yes "$FULLPATH_OSM_OSRM" >/dev/null; then
        log "detected processed osrm files are a different version to the osrm binary, reprocessing"
        REEXTRACT=1
    elif [ /data/"$OSM_PBF" -nt "$FULLPATH_OSM_OSRM" ]; then
        log "detected new /data/"$OSM_PBF" file, reprocessing"
        REEXTRACT=1
    fi
fi

if [ "$REDOWNLOAD" -o "$REEXTRACT" -o ! -f "$FULLPATH_OSM_OSRM" ]; then
    log "reprocessing osrm files"
    gosu osm mkdir -p /data/profile/"$PROFILE_DIR"

    # another container could be downloading "$DATA_DIR/$OSM_PBF", so we'll wait for the lock to release
    gosu osm flock "$DATA_DIR/$OSM_PBF".lock true && rm -f "$DATA_DIR/$OSM_PBF".lock

    ( cd /data && \
        gosu osm osrm-extract -t "$NPROCS" -p "$PROFILE" /data/"$OSM_PBF" && \
        gosu osm osrm-partition -t "$NPROCS" /data/"$OSM_OSRM" && \
        gosu osm osrm-customize -t "$NPROCS" /data/"$OSM_OSRM" && \
        mv /data/"$OSM_OSRM"* /data/profile/"$PROFILE_DIR"  || {
            log "osrm error processing /data/$OSM_PBF, exit 10"
            exit 10
        }
    )
fi

cd /
rm -f /data/osrm-backend.lock
log "initalised successfully"

if [ "$#" -gt 0 ]; then
    if [ "$1" = osrm-routed ]; then
        exec gosu osm "$@"
    fi

    exec "$@"
fi

exec gosu osm osrm-routed -t "$NPROCS" --algorithm "$OSRM_ALGORITHM" /data/profile/"$PROFILE_DIR"/"$OSM_OSRM"
