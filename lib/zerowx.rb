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
end

require "zerowx/api"
require "zerowx/national_weather_service"
require "zerowx/weather_underground"
require "zerowx/app"

