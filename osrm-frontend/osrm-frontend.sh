#!/bin/sh

set -e

if [ -f /usr/local/etc/osm-config.sh ]; then
    . /usr/local/etc/osm-config.sh
else
    log () {
        echo -n `date "+%Y-%m-%d %H:%M:%S+%Z"` "-- $0: $@"
    }
    log "/usr/local/etc/osm-config.sh not found, $0 is probably going to error and exit"
fi

log starting

if ! hash curl > /dev/null || ! hash su-exec > /dev/null; then
	apk --no-cache add curl su-exec
fi

if ! id osm &> /dev/null; then
	adduser -D osm &> /dev/null
fi

if ! id osrm &> /dev/null; then
	adduser -D osrm &> /dev/null
fi

cd /src/src && \
  	patch < ../gelinger777-3683985.patch

cd /src && \
	chown -R osm /src

if [ "$#" -gt 0 ]; then
	exec "$@"
fi

exec su-exec osm npm start
