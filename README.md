# maps-docker-compose

It should init into a working OpenStreetMap server with tiles, osrm and vroom, and nominatim.

The file `postgres/postgresql.conf` out of the box is set for a system with about 16GB 
ram and 4 cores. Check out https://pgtune.leopard.in.ua/#/ to get better starting values 
for your system

Edit `osm.env` with the pbf you want to import, I've only tested with geofabrik's files
and server. Basically I've only tested with the values supplied, for example I haven't 
tested with a different POSTGRES_USER.

In `osm-config.sh` NPROCS sets the number of cores to use by various processes, 
it's set to use all cores by default. You can add (eg) `NPROCS=2` to osm.env to 
set them to use 2 cores. It's not the total number of cores all the processes in the
various containers can use added up together, it sets various processes to NPROCS
cores and those various processes could run at the same time.

osm-config.sh is run at the beginning of all containers in this project. You can
add shells scripts with a file extension of .sh to the directory /osm-config.d 
to be sourced by osm-config.sh to setup or extend the container however you like. 

Edit `osrm-frontend/leaflet_options.js` to set things like the starting geo coords and zoom.  

`nginx/default.conf` will likely need to be tweaked but works for me out of the box.

You can add database index and other database changes by add a file 

After running `docker-compose up -d` depending on what pbf you've configured to import,
it will download a gigabyte or more, then process/import/setup. It might take many hours
depending on how fast your internet and server is, it takes my system at least 6 hours and
that's mainly time spent initialising nominatim. You can use `docker-compose-no-nominatim.yml`
to setup just the tile and routing services which takes me under an hour for the australia pbf.
 
After it finishes importing, `renderd-initdb` and `nominatim-initdb` will exit 0. 
If the *-initdb containers error and exit > 0, they will retry 3 times then sleep for 
3 hours, if they fail again, they will sleep for 4 hours, then 5 hours, etc. 
This is because of the large files they need to download and to stop them from 
potentially hammering the servers hosting the large files.
 
The osrm-backend on container on startup will detect if the binary has updated with a 
`docker-compose pull` and regenerate the osrm storage files.

If you `grep -r maps.localnet *` in the `maps-docker-compose` directory, you'll see every file 
you'll need to edit if you want to assign a domain name. Otherwise for testing you can edit
your `/etc/hosts` file with (ie) `127.0.0.1 maps.localnet nominatim.maps.localnet` if your browser
is on the same host as the docker containers. Then after it's finished starting up, you can in a 
web browser browse to `http://maps.localnet:8000` and `http://nominatim.maps.localnet:8000`

I'm happy to hear about any comments or issues, open an issue in github.
