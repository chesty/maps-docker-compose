'use strict';

var L = require('leaflet');

var streets = L.tileLayer('http://renderd.internal.kkts.com.au/osm_tiles/{z}/{x}/{y}.png', {}),
  small_components = L.tileLayer('https://tools.geofabrik.de/osmi/tiles/routing_i/{z}/{x}/{y}.png', {});

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
    path: 'http://192.168.1.55:5000/route/v1'
  }],
  layer: [{
    'Mapbox Streets': streets
  }],
  overlay: {
    'Small Components': small_components
  },
  baselayer: {
    one: streets
  }
};

