#!/bin/sh

if ! hash curl &> /dev/null || ! hash su-exec &> /dev/null; then
	apk --no-cache add curl su-exec
fi

if ! id osm &> /dev/null; then
	adduser -D osm &> /dev/null
fi

if ! id osrm &> /dev/null; then
	adduser -D osrm &> /dev/null
fi

cd /src && \
	chown -R osm /src && \

if [ "$#" -gt 0 ]; then
	exec "$@"
fi

exec su-exec osm npm start
