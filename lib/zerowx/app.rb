module ZeroWx

  class App < Sinatra::Base
    set :root, File.expand_path(__FILE__ + "/../../../")

    def initialize(*args)
      super
      Api.cache_server = Dalli::Client.new "127.0.0.1:11211"
      # Api.cache_enabled = false
      @wu = WeatherUnderground.new
      @nws = NationalWeatherService.new
    end

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html
    end

    get "/" do
      # stations list is filled out from localstorage
      @stations = []
      erb :stations
    end

    get "/about" do
      erb :about, :layout => false
    end

    get "/add_station" do
      erb :search, :layout => false
    end

    # for reload on search page
    get "/search" do
      redirect to("/")
    end

    post "/search" do
      if params[:lat] && params[:lon]
        @stations = @wu.stations_by_coords(params[:lat].to_f, params[:lon].to_f)
      elsif params[:location]
        @stations = @wu.stations_by_query(params[:location])
      else
        @stations = []
      end

      erb :search_results, :layout => false
    end

    get "/weather/:station_id" do
      @conditions = @wu.current_conditions(params[:station_id]).struct

      @location = @conditions.location.city + ", " + @conditions.location.state
      @name = @conditions.location.full.gsub(/\s+/, " ")
      neighborhood = @conditions.location.neighborhood.gsub(/\s+/, " ")
      neighborhood = @location if neighborhood == ""

      # for station info for saving to localstorage
      @station = {
        :id => params["station_id"],
        :name => neighborhood,
        :location => @location
      }

      lat, lon = @conditions.location.latitude.to_f, @conditions.location.longitude.to_f

      @forecast = @wu.forecast "#{lat},#{lon}"
      @history = @wu.daily_history params[:station_id]
      @text_forecast = @nws.forecast(lat, lon).text_forecast

      hourly = @nws.hourly_forecast(lat, lon)
      now = Time.now

      current_hour = Time.mktime(now.year, now.month, now.day, now.hour)
      # increments: 10 minutes, 60 minutes.
      hours_back = 12
      hours_forward = 36

      hours = (-hours_back..hours_forward).to_a.map { |o| current_hour + (o * 60 * 60) }
      times = (-hours_back * 6).step(hours_forward * 6).to_a.map { |t| current_hour + (t * 10 * 60) }

      @temperatures = hours.map { |t| t < now ? nil : hourly.temp[t] }
      @wind_speeds = hours.map { |t| t < now ? nil : hourly.wind[t] }
      @wind_gusts = hours.map { |t| t < now ? nil : hourly.gust[t] }
      @precipitation = hours[0...(hours.size-1)].map { |t| t < now ? nil : hourly.precip[t] }
      @cloud_cover = hours[0...(hours.size-1)].map { |t| t < now ? nil : hourly.cloud_cover[t] }
      @current_time = times.map do |t|
        offset = now.to_i - t.to_i
        (offset >= 0 && offset < 10 * 60) ? 1 : nil
      end

      sunrise = @forecast.moon_phase.sunrise.hour.to_i * 60 + @forecast.moon_phase.sunrise.minute.to_i
      sunset = @forecast.moon_phase.sunset.hour.to_i * 60 + @forecast.moon_phase.sunset.minute.to_i
      daytime = sunrise..sunset
      @night_day = times.map do |t|
        daytime.include?(t.hour * 60 + t.min) ? nil : 1
      end
      @hour_marks = hours.map { |t| t.hour % 6 == 0 ? 1 : nil }

      now = Time.now
      start_time = Time.mktime(now.year, now.month, now.day)
      end_time = Time.mktime(now.year, now.month, now.day, now.hour, (now.min / 10.0).floor * 10)

      @history.each do |h|
        h["Time"] = Time.parse(h["Time"])
      end

      @temp_history = times.map do |t|
        time_range = (t.to_i - 10 * 30)..(t.to_i + 10 * 30)
        temps = @history.select { |h| time_range.include? h["Time"].to_i }.map { |h| h["TemperatureF"].to_i }
        if temps.empty?
          nil
        else
          temps.inject(0) { |m,v| m + v } / temps.size.to_f # average temperature for this time range
        end
      end
      # remove trailing nils:
      @temp_history.pop while @temp_history.size > 0 && @temp_history.last.nil?

      @wind_history = times.map do |t|
        time_range = (t.to_i - 10*30)..(t.to_i + 10 * 30)
        speeds = @history.select { |h| time_range.include? h["Time"].to_i }.map { |h| h["WindSpeedMPH"].to_i }
        if speeds.empty?
          nil
        else
          speeds.inject(0) { |m,v| m + v } / speeds.size.to_f # average temperature for this time range
        end
      end
      @wind_history.pop while @wind_history.size > 0 && @wind_history.last.nil?

      @gust_history = times.map do |t|
        time_range = (t.to_i - 10*30)..(t.to_i + 10 * 30)
        speeds = @history.select { |h| time_range.include? h["Time"].to_i }.map { |h| h["WindSpeedGustMPH"].to_i }
        if speeds.empty?
          nil
        else
          speeds.inject(0) { |m,v| m + v } / speeds.size.to_f # average temperature for this time range
        end
      end
      @gust_history.pop while @gust_history.size > 0 && @gust_history.last.nil?

      erb :weather, :layout => false
    end

  end

end
