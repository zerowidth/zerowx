require "sinatra/base"
require "erb"
require "patron"

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
      # @history = @wu.daily_history("KCOBOULD29")
      erb :index
    end
  end

  class Api

    Error = Class.new(StandardError)

    class << self
      attr_accessor :base_url
    end

    attr_reader :http

    def initialize
      @http = Patron::Session.new
      http.base_url = self.class.base_url or raise "no base url!"
    end

    def get(url, params)
      response = http.get url, params
      if response.status >= 300
        raise Error, "HTTP #{response.code}\n#{response.body}"
      else
        puts "*** #{url} #{params.inspect} ***"
        puts response.body
        return response
      end
    end

    def xml_get(url, params={})
      response = get url, params
      doc = Nokogiri::XML.parse(response.body)
      return hashify(doc)
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
      FasterCSV.parse(doc, :headers => true, :return_headers => false) do |row|
        data << row.to_hash
      end
      return data
    end

  end

  class WeatherUnderground < Api
    self.base_url = "http://api.wunderground.com"

    def current_conditions(station_id)
      xml_get("/weatherstation/WXCurrentObXML.asp?ID=#{station_id}")["current_observation"]
    end

    def forecast(query)
      xml_get("/auto/wui/geo/ForecastXML/index.xml?query=#{query}")["forecast"]
    end

    def daily_history(station_id)
      csv_get "/weatherstation/WXDailyHistory.asp?ID=#{station_id}&format=1"
    end
  end

  class NationalWeatherService < Api
  end

end

