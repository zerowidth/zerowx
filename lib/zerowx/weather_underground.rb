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
      locations = hash_get("/auto/wui/geo/GeoLookupXML/index.xml?query=#{lat},#{lon}", :cache => 60)["location"]
      locations["nearby_weather_stations"]["pws"]["station"].sort_by { |s| s["distance_km"].to_f }
    end

    def stations_by_query(query)
      query = URI.escape(query)
      locations = hash_get("/auto/wui/geo/GeoLookupXML/index.xml?query=#{query}", :cache => 60)["location"]
      locations["nearby_weather_stations"]["pws"]["station"].sort_by { |s| s["distance_km"].to_f }
    end
  end

end
