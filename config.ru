$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), "lib")))
require "geminabox"

Geminabox.repos = ['http://rubygems.org']
Geminabox.enable_proxy_cache = true
run Geminabox.new
