module ZeroWx

  class WeatherUnderground < Api
    self.base_url = "http://api.wunderground.com"

    def current_conditions(station_id)
      hash_get("/weatherstation/WXCurrentObXML.asp?ID=#{station_id}", :cache => 60)["current_observation"]
    end

    def forecast(query)
      hash_get("/auto/wui/geo/ForecastXML/index.xml?query=#{query}", :cache => 900)["forecast"]
    end

    def daily_history(station_id)
      csv = csv_get "/weatherstation/WXDailyHistory.asp?ID=#{station_id}&format=1", :cache => 60
      now = Time.now
      if now.hour < 12
        yesterday = now - 12 * 60 * 60
        older = csv_get "/weatherstation/WXDailyHistory.asp?ID=#{station_id}&format=1&year=#{yesterday.year}&month=#{yesterday.month}&day=#{yesterday.day}", :cache => 60
        csv = older + csv
      end
      return csv
    end

    def stations_by_coords(lat, lon)
      locations = hash_get("/auto/wui/geo/GeoLookupXML/index.xml?query=#{lat},#{lon}", :cache => 900)["location"]
      stations_from_locations(locations)
    end

    def stations_by_query(query)
      query = URI.escape(query)
      locations = hash_get("/auto/wui/geo/GeoLookupXML/index.xml?query=#{query}", :cache => 900)["location"]
      stations_from_locations(locations)
    end

    protected

    def stations_from_locations(locations)
      stations = reformat_stations(locations["nearby_weather_stations"]["pws"]["station"])
      stations.sort_by { |s| s["distance_km"].to_f }
    end

    def reformat_stations(stations)
      stations.each do |station|
        neighborhood = station["neighborhood"].strip.gsub(/\s+/, " ")
        location = "#{station["city"]}, #{station["state"]}"

        station["name"] = neighborhood == "" ? location : neighborhood
        station["location"] = location
      end
      stations
    end
  end

end
