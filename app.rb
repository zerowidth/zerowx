require "sinatra/base"
require "erb"

class App < Sinatra::Base
  set :app_file, __FILE__

  get "/" do
    erb :index
  end
end
