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

wait_for_server () {
    server_host=$1
    server_port=$2
    : ${WFS_SLEEP:=15}
    while true; do
        log -n "Checking $server_host $server_port status... "

        if nc -zu "$server_host" 1 | grep -q "Unknown host"; then
            log "host $server_host not found, returning 1"
            return 1
        fi

        nc -z "$server_host" "$server_port" || {
            echo "$server_host is warming up. Trying again in $WFS_SLEEP seconds..."
            sleep $WFS_SLEEP
            continue
        }

        echo "$server_host is running and ready to process requests"
        return 0
    done
}

if ! hash curl > /dev/null 2>&1 || ! hash gosu > /dev/null 2>&1 || ! hash nc > /dev/null 2>&1 || ! hash psql > /dev/null 2>&1 ; then
    apt update && apt install -y gosu curl netcat postgresql-client
fi

if ! id osm > /dev/null 2>&1 ; then
    useradd --create-home osm &> /dev/null
fi

if ! id osrm > /dev/null 2>&1 ; then
    useradd --create-home osrm &> /dev/null
fi

if ! id postgres > /dev/null 2>&1 ; then
    useradd --create-home postgres &> /dev/null
fi

: ${PROFILE:=/opt/car.lua}
: ${PROFILE_DIR:=$(basename "$PROFILE" .lua)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
export PROFILE PROFILE_DIR OSM_OSRM

log_env

check_lockfile () {
    if [ -z "$1" ]; then
        log "check_lockfile <lockfile> [log prefix]"
        return 0
    fi
    LOCKFILE="$1"

    if [ -f "$LOCKFILE" ]; then
      log "$2 detected previous run didn't finish successfully, rerunning"
        eval `grep "restartcount=[0-9]\+" "$LOCKFILE"`
        restartcount=$(( $restartcount + 1 ))
        if [ "$restartcount" -gt 2 ]; then
            if [ "$restartcount" -gt 24 ]; then
                restartcount=24
            fi
            log "$2 has failed $restartcount times before, sleeping for $(( $restartcount * 3600 )) seconds"
            sleep $(( $restartcount * 3600 ))
        fi
        echo "restartcount=$restartcount" > "$LOCKFILE"
        return 1
    fi

    echo "restartcount=0" > "$LOCKFILE"
    eval `grep "restartcount=[0-9]\+" "$LOCKFILE"`
    return 0
}

check_lockfile /data/osrm-routed.lock "$0" || REDOWNLOAD=1

# mainly so 2 containers aren't trying to download the pbf at the same time.
wait_for_server renderd 7653

if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
    log "downloading $OSM_PBF_URL"
    gosu osm mkdir -p /data/osmosis
    gosu osm curl "$OSM_PBF_UPDATE_URL"/state.txt -o /data/osmosis/state.txt || {
        log "error downloading ${OSM_PBF_UPDATE_URL}/state.txt, exit 7"; exit 7; }
    gosu osm curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL" || {
        log "error downloading $OSM_PBF_URL, exit 8"; exit 8; }
    gosu osm curl -L -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5 || {
        log "error downloading ${OSM_PBF_URL}.md5, exit 9"; exit 9; }
    ( cd /data && \
        gosu osm md5sum -c "$OSM_PBF".md5 ) || {
            rm -f /data/"$OSM_PBF".md5 /data/"$OSM_PBF" /data/osmosis/state.txt
            log "md5sum mismatch on /data/$OSM_PBF, exit 4"
            exit 4
        }
    REINITDB=1
fi

# detect if binaries are a different version to the ones used to process the previous osm files,
# and reprocess if they are different.
: ${OSRM_ALGORITHM:="MLD"}
if [ -f /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" ]; then
    if ! gosu osm osrm-routed --algorithm "$OSRM_ALGORITHM" --trial=yes /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" >/dev/null; then
        log "detected processed osrm files are a different version to the osrm binary, reprocessing"
        REEXTRACT=1
    fi
fi

if [ "$REDOWNLOAD" -o "$REEXTRACT" -o ! -f /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" ]; then
    log "reprocessing osrm files"
    if [ ! -d /data/"$PROFILE_DIR" ]; then
        gosu osm mkdir -p /data/profile/"$PROFILE_DIR"
    fi
    ( cd /data && \
        gosu osm osrm-extract -p "$PROFILE" /data/"$OSM_PBF" && \
        gosu osm osrm-partition -t "$NPROCS" /data/"$OSM_OSRM" && \
        gosu osm osrm-customize -t "$NPROCS" /data/"$OSM_OSRM" && \
        mv /data/"$OSM_OSRM"* /data/profile/"$PROFILE_DIR" && \
        osrm-extract -v > /data/osrm.version || {
            rm -f /data/"$OSM_OSRM"* /data/osrm.version
            log "osrm error processing /data/$OSM_PBF, exit 10"
            exit 10
        }
    )
fi

cd /
rm -f /data/osrm-routed.lock
log "initalised successfully"

if [ "$#" -gt 0 ]; then
    exec "$@"
fi
exec gosu osm osrm-routed -t "$NPROCS" --algorithm "$OSRM_ALGORITHM" /data/profile/"$PROFILE_DIR"/"$OSM_OSRM"
