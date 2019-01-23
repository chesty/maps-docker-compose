# maps-docker-compose

It should init into a working OpenStreetMap server with tiles, osrm and vroom, and nominatim.
You'll want to edit the following files: 

- `postgres/postgresql.conf` out of the box it's set for a system with about 16GB 
ram and 4 cores. Check out https://pgtune.leopard.in.ua/#/ to get better starting values for your system
- `osm.env` with the pbf you want to import
- `osm-config.sh` NPROCS sets the number of cores to use, it's set to use all cores, you can change it to
a integer like 2 for example, that is `NPROCS=2`. osm-config.sh is run at the beginning of all containers
in this project, so you can use it as a hook to set up your containers however you like. It runs as root.
- `osrm-frontend/leaflet_options.js` 
- `nginx/default.conf` will likely need to be tweaked.

After running `docker-compose up -d` depending on what pbf you've configured to import,
it will download a gigabyte or more, then process/import/setup. It might take many hours
depending on how fast your internet and server is. After it finishes importing, 
`renderd-initdb` and `nominatim-initdb` will exit 0. If the *-initdb containers error and exit > 0, they will
retry 3 times then sleep for 3 hours, if they fail again, they will sleep for 4 hours, then 5 hours,
etc. This is because of the large files they need to download and to stop them from hammering the servers
hosting the large files.
 
The osrm-backend container will detect if the binary gets updated with a `docker-compose pull` and regenerate the 
osrm files.

If you `grep -r maps.localnet *` in the `maps-docker-compose` directory, you'll see every file 
you'll need to edit if you want to assign a domain name. Otherwise for testing you can edit
your `/etc/hosts` file with (ie) `127.0.0.1 maps.localnet nominatim.maps.localnet` if your browser
is on the same host as the docker containers. Then after it's finished starting up, you can in a web browser browse to
`http://maps.localnet:8000` and `http://nominatim.maps.localnet:8000`

I'm happy to hear about any comments or issues, open an issue in github.
