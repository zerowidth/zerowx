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

  class App < Sinatra::Base
    set :app_file, __FILE__

    attr_reader :wu

    def initialize(*args)
      super
      Cache.server = Dalli::Client.new "127.0.0.1:11211", :expires_in => 60
      @wu = WeatherUnderground.new
      @nws = NationalWeatherService.new
    end

    helpers do
      include Rack::Utils
      alias_method :h, :escape_html
    end

    get "/" do
      @conditions = @wu.current_conditions("KCOBOULD29")
      @forecast = @wu.forecast("80305")
      @history = @wu.daily_history("KCOBOULD29")

      hourly = @nws.hourly_forecast

      now = Time.now
      current_hour = Time.mktime(now.year, now.month, now.day, now.hour)
      hours = (-12..36).to_a.map { |o| current_hour + (o * 60 * 60) }
      times = -12.step(36, 0.25).to_a.map { |t| current_hour + (t * 60 * 60) }

      # offset = hourly.times.index { |t| t >= hours.first && t <= hours.last }
      # puts "offset is #{offset}"
      # @temperatures = hourly.temperatures[offset..(offset + hours.size)]
      @temperatures = hours.map { |t| hourly.temp[t] }

      sunrise = @forecast["moon_phase"]["sunrise"]["hour"].to_i * 60 + @forecast["moon_phase"]["sunrise"]["minute"].to_i
      sunset = @forecast["moon_phase"]["sunset"]["hour"].to_i * 60 + @forecast["moon_phase"]["sunset"]["minute"].to_i
      daytime = sunrise..sunset
      @night_day = times.map do |t|
        daytime.include?(t.hour * 60 + t.min) ? 1 : nil
      end
      @hour_marks = hours.map { |t| t.hour % 6 == 0 ? 1 : nil }

      now = Time.now
      start_time = Time.mktime(now.year, now.month, now.day)
      end_time = Time.mktime(now.year, now.month, now.day, now.hour, (now.min / 15.0).floor * 15)

      @history.each do |h|
        h["Time"] = Time.parse(h["Time"])
      end

      @temp_history = times.map do |t|
        time_range = (t.to_i - 15*30)..(t.to_i + 15 * 30)
        temps = @history.select { |h| time_range.include? h["Time"].to_i }.map { |h| h["TemperatureF"].to_i }
        if temps.empty?
          nil
        else
          temps.inject(0) { |m,v| m + v } / temps.size.to_f # average temperature for this time range
        end
      end
      # remove trailing nils:
      @temp_history.pop while @temp_history.size > 0 && !@temp_history.last

      puts "-" * 80

      erb :index
    end
  end

  module Cache
    class << self
      attr_accessor :server
    end

    def cache(method_name, ttl)
      method = instance_method(method_name)
      define_method method_name do |*args|
        # key = ([method_name] + args).map {|v| v.to_s }.join(":")
        key = "#{method_name}:#{args.hash}"
        puts "*** retrieving cached value for #{method_name} #{args.inspect}"
        return Cache.server.fetch(key, ttl) do
          puts "*** generating cached value for #{method_name} #{args.inspect}"
          method.bind(self).call(*args)
        end
      end
    end
  end

  class Api
    extend Cache

    Error = Class.new(StandardError)

    class << self
      attr_accessor :base_url
    end

    attr_reader :http

    def initialize
      @http = Patron::Session.new
      http.timeout = 30
      http.base_url = self.class.base_url or raise "no base url!"
    end

    def get(url, params)
      response = http.get url, params
      if response.status >= 300
        raise Error, "HTTP #{response.code}\n#{response.body}"
      else
        # puts "*** #{url} #{params.inspect} ***"
        # puts response.body
        return response
      end
    end

    def hash_get(url, params={})
      response = get url, params
      doc = Nokogiri::XML.parse(response.body)
      return hashify(doc)
    end

    def xml_get(url, params={})
      response = get url, params
      return Nokogiri::XML.parse(response.body)
    end

    def csv_get(url, params={})
      response = get url, params
      return csv_data(response.body)
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

  class WeatherUnderground < Api
    self.base_url = "http://api.wunderground.com"

    def current_conditions(station_id)
      hash_get("/weatherstation/WXCurrentObXML.asp?ID=#{station_id}")["current_observation"]
    end
    cache :current_conditions, 60

    def forecast(query)
      hash_get("/auto/wui/geo/ForecastXML/index.xml?query=#{query}")["forecast"]
    end
    cache :forecast, 60

    def daily_history(station_id)
      csv_get "/weatherstation/WXDailyHistory.asp?ID=#{station_id}&format=1"
    end
    cache :daily_history, 60
  end

  class NationalWeatherService < Api
    self.base_url = "http://forecast.weather.gov"

    class HourlyForecast
      attr_reader :doc
      def initialize(doc)
        @doc = doc
      end

      def temperatures
        return doc.xpath("/dwml/data/parameters/temperature[@type='hourly']/value").map do |temp|
          if temp.content.empty?
            nil
          else
            temp.content.to_i
          end
        end
      end

      def times
        return doc.xpath("/dwml/data/time-layout/start-valid-time").map { |t| Time.parse(t.content) }
      end

      def temp
        @temp ||= Hash[times.zip(temperatures)]
      end

    end

    def hourly_forecast
      doc = xml_get "/MapClick.php?lat=40.02690&lon=-105.25100&FcstType=digitalDWML"
      return HourlyForecast.new(doc)
    end

  end

end

