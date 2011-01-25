require "rubygems"
require "bundler"

Bundler.require :default

ENV["TZ"] = "US/Mountain"

$:.push File.expand_path("../lib", __FILE__)
require "zerowx"

run ZeroWx::App
