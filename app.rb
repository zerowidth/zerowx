require "sinatra/base"
require "erb"
require "patron"
require "json"

require "time"

require "csv"
if CSV.const_defined? :Reader
  require "fastercsv"
else
  FasterCSV = CSV
end

module ZeroWx

  class Api
    Error = Class.new(StandardError)

    class << self
      attr_accessor :base_url
      attr_accessor :cache_server
    end

    attr_reader :http

    def initialize
      @http = Patron::Session.new
      http.timeout = 30
      http.base_url = self.class.base_url or raise "no base url!"
    end

    def cache(key, ttl)
      if Api.cache_server
        puts "cache get: #{key}"
        Api.cache_server.fetch(key, ttl) do
          puts "cache set: #{key} - #{ttl}"
          yield
        end
      else
        yield
      end
    end

    def get(url, opts)
      ttl = opts.delete :cache
      return cache url, ttl do
        response = http.get url
        if response.status >= 300
          raise Error, "HTTP #{response.code}\n#{response.body}"
        end
        response.body
      end
    end

    def hash_get(url, opts={})
      response = get url, opts
      doc = Nokogiri::XML.parse(response)
      return hashify(doc)
    end

    def xml_get(url, opts={})
      response = get url, opts
      return Nokogiri::XML.parse(response)
    end

    def csv_get(url, opts={})
      response = get url, opts
      return csv_data(response)
    end

    def hashify(xml)
      h = {}
      if xml.element_children.empty?
        return xml.content
      else
        xml.element_children.each do |child|
          if h[child.name]
            h[child.name] = [h[child.name]] unless h[child.name].kind_of?(Array)
            h[child.name].push hashify(child)
          else
            h[child.name] = hashify child
          end
        end
        return h
      end
    end

    def csv_data(doc)
      data = []
      doc = doc.gsub(/<[^>]+>/, "")
      FasterCSV.parse(doc, :headers => true, :return_headers => false) do |row|
        data << row.to_hash
      end
      return data.reject { |h| h.empty? }
    end

  end


  class App < Sinatra::Base
    set :app_file, __FILE__

    def initialize(*args)
      super
      Api.cache_server = Dalli::Client.new "127.0.0.1:11211"
      @wu = WeatherUnderground.new
      @nws = NationalWeatherService.new
    end

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html
    end

    get "/" do
      @conditions = @wu.current_conditions "KCOBOULD29"
      @forecast = @wu.forecast "80305"
      @history = @wu.daily_history "KCOBOULD29"
      @text_forecast = @nws.forecast.text_forecast

      hourly = @nws.hourly_forecast

      now = Time.now

      current_hour = Time.mktime(now.year, now.month, now.day, now.hour)
      hours = (-12..38).to_a.map { |o| current_hour + (o * 60 * 60) }
      times = -72.step(228).to_a.map { |t| current_hour + (t * 10 * 60) }

      @temperatures = hours.map { |t| t < now ? nil : hourly.temp[t] }
      @wind_speeds = hours.map { |t| t < now ? nil : hourly.wind[t] }
      @wind_gusts = hours.map { |t| t < now ? nil : hourly.gust[t] }
      @precipitation = hours[0...(hours.size-1)].map { |t| t < now ? nil : hourly.precip[t] }
      @cloud_cover = hours[0...(hours.size-1)].map { |t| t < now ? nil : hourly.cloud_cover[t] }
      @current_time = times.map do |t|
        offset = now.to_i - t.to_i
        (offset >= 0 && offset < 10 * 60) ? 1 : nil
      end

      sunrise = @forecast["moon_phase"]["sunrise"]["hour"].to_i * 60 + @forecast["moon_phase"]["sunrise"]["minute"].to_i
      sunset = @forecast["moon_phase"]["sunset"]["hour"].to_i * 60 + @forecast["moon_phase"]["sunset"]["minute"].to_i
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

      puts "-" * 80

      erb :index
    end

  end

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

  class NationalWeatherService < Api
    self.base_url = "http://forecast.weather.gov"

    class HourlyForecast

      attr_reader :doc

      def initialize(doc)
        @doc = doc
      end

      def times
        return doc.xpath("/dwml/data/time-layout/start-valid-time").map { |t| Time.parse(t.content) }
      end

      def temp
        unless @temp
          temps = doc.xpath("/dwml/data/parameters/temperature[@type='hourly']/value").map do |temp|
            temp.content.empty? ? nil : temp.content.to_i
          end
          @temp = Hash[times.zip(temps)]
        end
        @temp
      end

      def wind
        unless @wind
          winds = doc.xpath("/dwml/data/parameters/wind-speed[@type='sustained']/value").map do |speed|
            speed.content.empty? ? nil : speed.content.to_i
          end
          @wind = Hash[times.zip(winds)]
        end
        @wind
      end

      def gust
        unless @gust
          gusts = doc.xpath("/dwml/data/parameters/wind-speed[@type='gust']/value").map do |speed|
            speed.content.empty? ? nil : speed.content.to_i
          end
          @gust = Hash[times.zip(gusts)]
        end
        @gust
      end

      def precip
        unless @precip
          precipitation = doc.xpath("/dwml/data/parameters/probability-of-precipitation/value").map do |prob|
            prob.content.empty? || prob.content.to_i == 0 ? nil : prob.content.to_i
          end
          @precip = Hash[times.zip(precipitation)]
        end
        @precip
      end

      def cloud_cover
        unless @cloud_cover
          coverage = doc.xpath("/dwml/data/parameters/cloud-amount/value").map do |prob|
            prob.content.empty? || prob.content.to_i == 0 ? nil : prob.content.to_i
          end
          @cloud_cover = Hash[times.zip(coverage)]
        end
        @cloud_cover
      end
    end

    class Forecast

      attr_reader :doc

      def initialize(doc)
        @doc = doc
      end

      def text_forecast
        time_layout = doc.xpath("//time-layout").detect { |l| l.xpath("layout-key").first.content =~ /k-p12h-n1\d-\d/ }
        names = time_layout.xpath("start-valid-time").map { |x| x['period-name'] }
        text = doc.xpath("//wordedForecast/text").map { |t| t.content }
        names.zip(text)
      end

    end

    def hourly_forecast
      doc = xml_get "/MapClick.php?lat=40.02690&lon=-105.25100&FcstType=digitalDWML", :cache => 900
      return HourlyForecast.new(doc)
    end

    def forecast
      doc = xml_get "/MapClick.php?lat=40.02690&lon=-105.25100&FcstType=dwml", :cache => 900
      return Forecast.new(doc)
    end

  end

end

