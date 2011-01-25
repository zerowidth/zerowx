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
  end

end
