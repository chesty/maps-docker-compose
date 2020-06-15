'use strict';

var L = require('leaflet');

var streets = L.tileLayer('/osm_tiles/{z}/{x}/{y}.png', {});

module.exports = {
  defaultState: {
    center: L.latLng(-33.846467,151.116428),
    zoom: 12,
    waypoints: [],
    language: 'en',
    alternative: 0,
    layer: streets
  },
  services: [{
    label: 'Car (fastest)',
    path: '/osrm-backend/route/v1'
  }],
  layer: [{
    'Mapbox Streets': streets
  }],
  baselayer: {
    one: streets
  },
  nominatim: {
    url: '//nominatim.openstreetmap.org/'
  }
};

