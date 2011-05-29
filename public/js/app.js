window.log = function(){
  log.history = log.history || [];
  log.history.push(arguments);
  if(this.console){
    console.log( Array.prototype.slice.call(arguments) );
  }
};
(function(doc){
  var write = doc.write;
  doc.write = function(q){
    log('document.write(): ',arguments);
    if (/docwriteregexwhitelist/.test(q)) { write.apply(doc,arguments); }
  };
})(document);

var searchPosition = function(position) {
  $('#search div.error').fadeOut();

  $.mobile.changePage({
    url: '/search',
    type: 'post',
    data: {lat: position.coords.latitude, lon: position.coords.longitude}
  });
}

var geolocationError = function(error) {
  $.mobile.pageLoading(true);
  var $error = $('#search div.error');
  $error.find('p').html("Couldn't find your location: " + error.message);
  $error.fadeIn();
}

$('#geolocate').live('click', function() {
  $.mobile.pageLoading();
  // searchPosition({
  //   coords: {
  //     latitude: 40.01,
  //     longitude: -105.27
  //   }
  // });
  if(Modernizr.geolocation) {
    navigator.geolocation.getCurrentPosition(searchPosition, geolocationError);
  }
  else {
    geolocationError({message: "Sorry, location services aren't available or enabled"});
  }
  return false;
});

var stations = {
  list: function() {
    var data = localStorage.getItem('zerowx.stations');
    if(data) {
      return JSON.parse(data).stations;
    }
    else {
      return [];
    }
  },
  store: function(list) {
    localStorage.setItem('zerowx.stations', JSON.stringify({stations: list}));
  },
  ids: function() {
    return _.pluck(this.list(), 'id');
  },
  add: function(station) {
    var current = this.list();
    current.push(station);
    this.store(current);
  },
  remove: function(station_id) {
    var updated = _.reject(this.list(), function(station) {
      return station.id == station_id;
    });
    this.store(updated);
  }
};

$(document).bind("mobileinit", function(){
  // $.mobile.hashListeningEnabled = false;
});

$('[data-role=page]').live('pagebeforeshow', function(event) {
  var $page = $(event.target);

  if($page.attr('id') == 'weather') {
    var stationId = $page.data('stationId');

    if(_.indexOf(stations.ids(), stationId) >= 0) {
      $page.find('a.forget_station').show();
    }
    else {
      $page.find('a.remember_station').show();
    }
  }

  if($page.attr('id') == 'stations') {
    var $list = $page.find('ul#station_list');
    var template = $('#station_list_template').html();
    $list.html($.mustache(template, {stations: stations.list()}));
    $list.listview('refresh'); // reapply jqm styles
  }

});

$('#weather').live('pageshow', function(event) {
  var $page = $(event.target);
  var data = $.parseJSON($page.find('script.weather_data').html());
  drawWeatherGraph($page, data);
});


$('#weather a.remember_station').live('click', function() {
  var $page = $($.mobile.activePage);
  var station = JSON.parse($page.find('.station_info').html());
  stations.add(station);

  $page.find('a.remember_station').hide();
  $page.find('a.forget_station').show();

  return false;
});

$('#weather a.forget_station').live('click', function() {
  var $page = $($.mobile.activePage);
  var stationId = $page.data('stationId');
  stations.remove(stationId);

  $page.find('a.forget_station').hide();
  $page.find('a.remember_station').show();

  return false;
});

drawWeatherGraph = function($page, data) {
  // default is iphone size
  var ten_minute_size = 1;
  var hour_size = 6;
  var graph_height = 60;
  var cloud_height = 20;

  if($page.find('.graph').width() > 400) {
    ten_minute_size = 2;
    hour_size = 12;
    graph_height = 90;
    cloud_height = 30;
    $('.graph').css('height', '120px');
  }

  // draw night/day
  $page.find('.predictions').sparkline(
    data.night_day,
    {
      height: graph_height,
      type: 'bar',
      barSpacing: 0,
      barWidth: ten_minute_size,
      barColor: '#EEE',
      chartRangeMin: 0,
      chartRangeMax: 1
    }
  );

  // hour marks
  $page.find('.predictions').sparkline(
    data.hour_marks,
    {
      type: 'bar',
      composite: true,
      barSpacing: hour_size - 1,
      barWidth: 1,
      barColor: '#DDD',
      chartRangeMin: 0,
      chartRangeMax: 1
    }
  );

  // zero line
  $page.find('.predictions').sparkline(
    [0, 0],
    {
      composite: true,
      lineColor: '#DDD',
      chartRangeMin: 0,
      chartRangeMax: 1,
      minSpotColor: false,
      maxSpotColor: false,
      spotColor: false
    }
  );

  // wind gust predictions
  $page.find('.predictions').sparkline(
    data.wind_gusts,
    {
      composite: true,
      defaultPixelsPerValue: 4,
      fillColor: false,
      chartRangeMin: 0,
      chartRangeMax: data.max_w,
      lineColor: '#8F8',
      spotColor: false,
      minSpotColor: false,
      maxSpotColor: false
    }
  );

  // wind speed predictions
  $page.find('.predictions').sparkline(
    data.wind_speeds,
    {
      defaultPixelsPerValue: 4,
      fillColor: false,
      composite: true,
      chartRangeMin: 0,
      chartRangeMax: data.max_w,
      lineColor: '#0F0',
      spotColor: false,
      minSpotColor: false,
      maxSpotColor: false
    }
  );

  // temperature predictions
  $page.find('.predictions').sparkline(
    data.temperatures,
    {
      defaultPixelsPerValue: 4,
      fillColor: false,
      composite: true,
      chartRangeMin: data.min_t,
      chartRangeMax: data.max_t,
      lineColor: '#88F',
      minSpotColor: '#808',
      maxSpotColor: '#808',
      spotColor: false
    }
  );

  // current time marker
  // $page.find('.predictions').sparkline(
  //   data.current_time,
  //   {
  //     type: 'bar',
  //     composite: true,
  //     barSpacing: 0,
  //     barWidth: 1,
  //     barColor: '#F88',
  //     chartRangeMin: 0,
  //     chartRangeMax: 1
  //   }
  // );

  // wind gust history
  $page.find('.gust_history').sparkline(
    data.gust_history,
    {
      height: graph_height,
      fillColor: false,
      defaultPixelsPerValue: ten_minute_size,
      chartRangeMin: 0,
      chartRangeMax: data.max_w,
      lineColor: '#4C4',
      lineWidth: 1,
      spotColor: false,
      minSpotColor: false,
      maxSpotColor: false
    }
  );

  // wind speed history
  $page.find('.wind_history').sparkline(
    data.wind_history,
    {
      height: graph_height,
      fillColor: false,
      defaultPixelsPerValue: ten_minute_size,
      chartRangeMin: 0,
      chartRangeMax: data.max_w,
      lineColor: '#080',
      lineWidth: 1.5,
      spotColor: '#F00',
      minSpotColor: false,
      maxSpotColor: false
    }
  );

  // temperature history
  $page.find('.temp_history').sparkline(
    data.temp_history,
    {
      height: graph_height,
      fillColor: false,
      defaultPixelsPerValue: ten_minute_size,
      chartRangeMin: data.min_t,
      chartRangeMax: data.max_t,
      lineWidth: 1.5,
      spotColor: '#F00',
      minSpotColor: false,
      maxSpotColor: false
    }
  );

  // night/day for precip graph
  $page.find('.sky').sparkline(
    data.night_day,
    {
      height: cloud_height,
      type: 'bar',
      barSpacing: 0,
      barWidth: ten_minute_size,
      barColor: '#EEE',
      chartRangeMin: 0,
      chartRangeMax: 1
    }
  );

  // hour marks for sky graph
  $page.find('.sky').sparkline(
    data.hour_marks,
    {
      type: 'bar',
      composite: true,
      barSpacing: hour_size - 1,
      barWidth: 1,
      barColor: '#DDD',
      chartRangeMin: 0,
      chartRangeMax: 1
    }
  );

  // cloud cover predictions
  $page.find('.sky').sparkline(
    data.cloud_cover,
    {
      type: 'bar',
      composite: true,
      barSpacing: 1,
      barWidth: hour_size - 1,
      barColor: '#AAA',
      chartRangeMin: 0,
      chartRangeMax: 100
    }
  );

  // precipitation prediction
  $page.find('.sky').sparkline(
    data.precipitation,
    {
      type: 'bar',
      composite: true,
      barSpacing: 1,
      barWidth: hour_size - 1,
      barColor: '#8CF',
      chartRangeMin: 0,
      chartRangeMax: 100
    }
  );

  // current time marker
  // $page.find('.precipitation').sparkline(
  //   data.current_time,
  //   {
  //     type: 'bar',
  //     composite: true,
  //     barSpacing: 0,
  //     barWidth: 1,
  //     barColor: '#F88',
  //     chartRangeMin: 0,
  //     chartRangeMax: 1
  //   }
  // );
};
