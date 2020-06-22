#!/bin/sh

log () {
    if [ "$1" = "-n" ]; then
        shift
        echo -n `date "+%Y-%m-%d %H:%M:%S+%Z"` "-- $0: $@"
    else
        echo `date "+%Y-%m-%d %H:%M:%S+%Z"` "-- $0: $@"
    fi
}

log_env () {
    log `env | grep -v PASSWORD`
}

log "starting osm-config.sh"

# these will only be set if they aren't already set
: ${NPROCS:=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1)}
: ${OSM_PBF_URL:="http://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf"}
: ${OSM_PBF_UPDATE_URL:="http://download.geofabrik.de/australia-oceania/australia-updates"}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
: ${OSM2PGSQLCACHE:="2000"}
: ${POSTGRES_PASSWORD:="supersecret"}
: ${POSTGRES_HOST:="postgres"}
: ${POSTGRES_USER:="postgres"}
: ${POSTGRES_DB:="gis"}
: ${POSTGRES_PORT:="5432"}
: ${WFS_SLEEP:="30"}
: ${RENDERD_UPDATE_SLEEP:="86400"}

export NPROCS OSM_PBF_URL OSM_PBF_UPDATE_URL OSM_PBF OSM_PBF_BASENAME OSM_OSRM OSM_PBF OSM_PBF_BASENAME \
  OSM2PGSQLCACHE POSTGRES_PASSWORD  POSTGRES_HOST POSTGRES_DB POSTGRES_PORT WFS_SLEEP \
  RENDERD_UPDATE_SLEEP

log_env

for U in osm osrm postgres root "$POSTGRES_USER"; do
    if ! id "$U" >/dev/null 2>&1; then
        useradd -ms /bin/bash "$U"
    fi

    if [ ! -f ~"$U"/.pgpass ]; then
        if [ ! -d ~ ]; then
            mkdir -p ~
            chown "$U": ~
        fi
        (
            eval cd ~"$U"
            touch .pgpass
            chown "$U": .pgpass
            chmod 600 .pgpass
            echo "$POSTGRES_HOST:$POSTGRES_PORT:*:$POSTGRES_USER:$POSTGRES_PASSWORD" >> .pgpass
        )
    fi
done

if [ -d /osm-config.d ]; then
    for script in /osm-config.d/*.sh; do
        log "osm-config.sh running $script"
        . "$script"
    done
fi

config_specific_name () {
    if [ -z "$1" ]; then
        echo "$1 error config_specific_name <SUBCOMMAND>"
        return 1
    fi
    echo "$(basename $0)-$1-$POSTGRES_HOST-$POSTGRES_PORT-$POSTGRES_DB-$POSTGRES_USER" | tr -d '\000'  | tr -d '/'
}

check_lockfile () {
    if [ -z "$1" ]; then
        log "$SUBCOMMAND error check_lockfile <lockfile> [log prefix]"
        return 1
    fi

    LCK="$1"
    if [ -s "$LCK" ]; then
        log "$SUBCOMMAND $2 detected previous run didn't finish successfully"
        eval `grep "restartcount=[0-9]\+" "$LCK"`
        restartcount=$(( $restartcount + 1 ))
        echo "restartcount=$restartcount" > "$LCK"
        return 1
    fi

    echo "restartcount=0" > "$LCK"
    eval `grep "restartcount=[0-9]\+" "$LCK"`
    return 0
}

rate_limit () {
    if [ -z "$1" ]; then
        log "$SUBCOMMAND error rate_limit <lockfile> [log prefix]"
        return 1
    fi

    LCK="$1"
    if [ -s "$LCK" ]; then
        eval `grep "restartcount=[0-9]\+" "$LCK"`
        if [ "$restartcount" -gt 2 ]; then
            if [ "$restartcount" -gt 24 ]; then
                log "$SUBCOMMAND $2 failed more that 24 times, only sleeping for 24 hours"
                restartcount=24
            fi
            log "$SUBCOMMAND $2 sleeping for $(( $restartcount * 3600 )) seconds"
            sleep $(( $restartcount * 3600 ))
        fi
        return 1
    fi
    return 0
}

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

ensure_single_unique_container () {
    LOCKFILE="$DATA_DIR/$(config_specific_name "$SUBCOMMAND").lock"

    if [ "${FLOCKER}" != "$LOCKFILE" ]; then
        env FLOCKER="$LOCKFILE" flock -E 111 -Fen "$LOCKFILE" "$0" "$SUBCOMMAND" "$@" || EC=$?
        if [ "$EC" = 111 ]; then
            log "$SUBCOMMAND error already running, exit 19"
            return 19
        fi
        if [ -n "$EC" ]; then
            return $EC
        fi
        # we shouldn't get to this point, "$0" either exits or exec's a command
        # but we'll exit so "$0" doesn't run twice
        exit
    fi
}
