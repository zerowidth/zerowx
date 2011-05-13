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
  searchPosition({
    coords: {
      latitude: 40.01,
      longitude: -105.27
    }
  });
  return false;
});

