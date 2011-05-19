require "rubygems"
require "bundler"

Bundler.require :default

ENV["TZ"] = "US/Mountain"

$:.push File.expand_path("../lib", __FILE__)
require "zerowx"

use Rack::Reloader, 0 # no cooldown
run ZeroWx::App
