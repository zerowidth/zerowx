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

