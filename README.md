# maps-docker-compose

It should init into a working OpenStreetMap server with tiles, osrm and vroom, and nominatim.
You'll need to edit postgres/postgresql.conf with suitable values for your server,
edit osm.env with the pbf you want to import, also osrm-frontend/leaflet_options.js 
and nginx/default.conf will likely need to be tweaked.

