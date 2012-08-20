$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), "lib")))
require "geminabox"

Geminabox.repos = ['http://rubygems.org']
run Geminabox
