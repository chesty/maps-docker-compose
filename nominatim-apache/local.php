<?php

@define('CONST_Log_File', '/Nominatim/build/logpipe');
@define('CONST_Website_BaseURL', '/nominatim/');

// Replication settings
@define('CONST_Replication_Url', 'http://download.geofabrik.de/australia-oceania/australia-updates/');
@define('CONST_Replication_MaxInterval', '86400');
@define('CONST_Replication_Update_Interval', '86400');  // How often upstream publishes diffs
@define('CONST_Replication_Recheck_Interval', '3600'); // How long to sleep if no update found yet

@define('CONST_Default_Language', false);
// Appearance of the map in the debug interface.
@define('CONST_Default_Lat', -24.9932483);
@define('CONST_Default_Lon', 115.2323916);
@define('CONST_Default_Zoom', 4);
@define('CONST_Map_Tile_URL', '/osm_tiles/{z}/{x}/{y}.png');
@define('CONST_Map_Tile_Attribution', 'hammer'); // Set if tile source isn't osm.org

// @define('CONST_Osm2pgsql_Flatnode_File', '/tmp/flatnode.file');

// if you put your postgres password here, nominatim-apache doesn't need to share the run volume with postgres
// @define('CONST_Database_DSN', 'pgsql://postgres:supersecret@postgres/nominatim');
