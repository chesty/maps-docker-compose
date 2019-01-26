#!/bin/sh

alias log="echo " $@ "`date --iso-8601=seconds` -- $0: "
log_env () {
    log `env | grep -v PASSWORD`
}

log starting

: ${NPROCS:=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1)}
: ${OSM_PBF:=$(basename "$OSM_PBF_URL")}
: ${OSM_PBF_BASENAME:=$(basename "$OSM_PBF" .osm.pbf)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}

export NPROCS OSM_PBF OSM_PBF_BASENAME OSM_OSRM

log_env

for U in osm osrm postgres root; do
    if id "$U" > /dev/null 2>&1 && [ ! -f ~"$U"/.pgpass ]; then
        if [ ! -d ~ ]; then
            mkdir ~
            chown "$U": ~
        fi
        ( eval cd ~"$U"; touch .pgpass; chown "$U": .pgpass; chmod 600 .pgpass; \
            echo "$POSTGRES_HOST:$POSTGRES_PORT:*:$POSTGRES_USER:$POSTGRES_PASSWORD" >> .pgpass; )
    fi
done

if [ -d /osm-config.d ]; then
    for script in /osm-config.d/*.sh; do
        log "running $script"
        . "$script"
    done
fi