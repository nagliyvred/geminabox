$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), "lib")))
require "geminabox"

Geminabox.repos = ['http://rubygems.org']
Geminabox.enable_proxy_cache = true
Geminabox.data = '/var/geminabox/data'
Geminabox.synchronize_schedule = '0 2 * * *'
run Geminabox.new
