#!/bin/sh

function wait_for_server () {

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

if ! hash curl &> /dev/null || ! hash su-exec &> /dev/null; then
	apk --no-cache add su-exec curl
fi

if ! id osrm &> /dev/null; then
	adduser -D osrm &> /dev/null
fi

. /data/config.sh

: ${PROFILE:=/opt/car.lua}
: ${PROFILE_DIR:=$(basename "$PROFILE" .lua)}
: ${OSM_OSRM:="$OSM_PBF_BASENAME".osrm}
export PROFILE PROFILE_DIR OSM_OSRM

# mainly so 2 containers aren't trying to download the pbf at the same time.
wait_for_server renderd 7653

if [ "$REDOWNLOAD" -o ! -f /data/"$OSM_PBF" -a "$OSM_PBF_URL" ]; then
	su-exec osrm curl -L -z /data/"$OSM_PBF" -o /data/"$OSM_PBF" "$OSM_PBF_URL"
	su-exec osrm curl -L -z /data/"$OSM_PBF".md5 -o /data/"$OSM_PBF".md5 "$OSM_PBF_URL".md5
	cd /data && \
		su-exec osrm md5sum -c "$OSM_PBF".md5 || exit 1
fi

if [ "$REDOWNLOAD" -o "$REEXTRACT" -o ! -f /data/profile/"$PROFILE_DIR"/"$OSM_OSRM" ]; then
	if [ ! -d /data/"$PROFILE_DIR" ]; then
		su-exec osrm mkdir -p /data/profile/"$PROFILE_DIR"
	fi
	su-exec osrm osrm-extract -p "$PROFILE" -t "$NPROCS" /data/"$OSM_PBF" && \
		su-exec osrm osrm-partition "$OSM_OSRM" && \
		su-exec osrm osrm-customize "$OSM_OSRM" && \
		mv /data/"$OSM_PBF".osrm* /data/profile/"$PROFILE_DIR"
fi

cd /

if [ "$@" ]; then
	exec "$@"
fi

exec su-exec osrm osrm-routed -t "$NPROCS" --algorithm mld /data/profile/"$PROFILE_DIR"/"$OSM_OSRM"

