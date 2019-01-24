#!/bin/sh

echo $0 called at `date  --iso-8601=seconds`

set -e
set -x

wait_for_server () {
    server_host=$1
    server_port=$2
    : ${WFS_SLEEP:=15}
    while true; do
        echo -n "Checking $server_host $server_port status... "

        if nc -zu "$server_host" 1 | grep -q "Unknown host"; then
            echo "host $server_host not found, returning 1" `print_time`
            return 1
        fi

        nc -z "$server_host" "$server_port" || {
            echo "$server_host is warming up. Trying again in $WFS_SLEEP seconds..."
            sleep $WFS_SLEEP
            continue
        }

        echo "$server_host is running and ready to process requests."
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

if [ -f /usr/local/etc/osm-config.sh ]; then
    . /usr/local/etc/osm-config.sh
else
    echo "/usr/local/etc/osm-config.sh not found, $0 is probably going to error and exit"
fi

: ${PROFILE:=/opt/car.lua}
: ${PROFILE_DIR:=$(basename "$PROFILE" .lua)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
export PROFILE PROFILE_DIR OSM_OSRM


if [ -f /data/osrm-routed.lock ]; then
    echo "Interrupted $0 detected, rerunning $0 at" `print_time`
    REDOWNLOAD=1
    eval `grep "reinitcount=[0-9]\+" /data/osrm-routed.lock`
    reinitcount=$(( $reinitcount + 1 ))
    echo "reinitcount=$reinitcount" > /data/osrm-routed.lock
    if [ "$reinitcount" -gt 2 ]; then
        echo "$0 has failed $reinitcount times before, sleeping for $(( $reinitcount * 3600 )) seconds at" `print_time`
        sleep $(( $reinitcount * 3600 ))
    fi
else
    echo "reinitcount=0" > /data/osrm-routed.lock
    eval `grep "reinitcount=[0-9]\+" /data/osrm-routed.lock`
fi

# mainly so 2 containers aren't trying to download the pbf at the same time.
wait_for_server renderd 7653

if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
    echo "$0 downloading $OSM_PBF_URL at" `print_time`
    gosu osm mkdir -p /data/osmosis
    gosu osm curl "$OSM_PBF_UPDATE_URL"/state.txt -o /data/osmosis/state.txt || {
        echo "error downloading ${OSM_PBF_UPDATE_URL}/state.txt, exit 7"; exit 7; }
    gosu osm curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL" || {
        echo "error downloading $OSM_PBF_URL, exit 8"; exit 8; }
    gosu osm curl -L -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5 || {
        echo "error downloading ${OSM_PBF_URL}.md5, exit 9"; exit 9; }
    ( cd /data && \
        gosu osm md5sum -c "$OSM_PBF".md5 ) || {
            rm -f /data/"$OSM_PBF".md5 /data/"$OSM_PBF"
            echo "md5sum mismatch on /data/$OSM_PBF, exit 4 at" `print_time`
            exit 4
        }
    REINITDB=1
fi

# detect if binaries are a different version to the ones used to process the previous osm files,
# and reprocess if they are different.
if [ -f /data/osrm.version ]; then
    if [ "`osrm-extract -v`" != "`cat /data/osrm.version`" ]; then
        echo "$0 detected different osrm binary version, reprocessing osm files at" `print_date`
        REEXTRACT=1
    fi
else
    REEXTRACT=1
fi

if [ "$REDOWNLOAD" -o "$REEXTRACT" -o ! -f /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" ]; then
    echo "$0 reprocessing osrm files at" `print_time`
    if [ ! -d /data/"$PROFILE_DIR" ]; then
        gosu osm mkdir -p /data/profile/"$PROFILE_DIR"
    fi
    ( cd /data && \
        gosu osm osrm-extract -p "$PROFILE" /data/"$OSM_PBF" && \
        gosu osm osrm-partition /data/"$OSM_OSRM" && \
        gosu osm osrm-customize /data/"$OSM_OSRM" && \
        mv /data/"$OSM_OSRM"* /data/profile/"$PROFILE_DIR" && \
        osrm-extract -v > /data/osrm.version || {
            rm -f /data/"$OSM_OSRM"* /data/osrm.version
            echo "$0 osrm error processing /data/$OSM_PBF, exit 10 at" `print_time`
            exit 10
        }
    )
fi

cd /
rm -f /data/osrm-routed.lock

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

echo "$0 initalised successfully at" `print_time`
exec gosu osm osrm-routed -t "$NPROCS" --algorithm mld /data/profile/"$PROFILE_DIR"/"$OSM_OSRM"
