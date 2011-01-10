require "rubygems"
require "bundler"

Bundler.require :default

ENV["TZ"] = "US/Mountain"

require "./app"
run ZeroWx::App
