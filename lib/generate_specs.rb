require 'rubygems'
require 'httpclient'

def unpack(filename, data)
  if filename.end_with?('gz')
    Gem.gunzip(data)
  else
    Gem.inflate(data)
  end
end

def pack(filename, data)
  if filename.end_with?("gz")
    Gem.gzip(data)
  else 
    Gem.deflate(data)
  end
end

def load_marshalled(filename, data)
  Marshal.load(unpack(filename, data))
end

def download_remote(url, filename)
  client = HTTPClient.new
  response = client.get(url, :follow_redirect => true)
  puts "response code is #{response.status}"
  #puts "response #{response.inspect}"
  response.content
  #Marshal.load(unpack(filename, response.content))
end

def marshal_to_file(data, filename)
  File.open(filename, 'wb') { |f| f.write(Gem.gzip(Marshal.dump(data))) }
end


FILES = [#'latest_specs.4.8.gz', 'prerelease_specs.4.8.gz', 'specs.4.8.gz',
  'Marshal.4.8.Z']
DIR="/Users/edudin/github/geminabox/data/"

FILES.each do |file|

  puts "handling #{file}"
  filename = DIR + '/local/' +  file
  data = File.open(filename) { |f| f.read }
  local = load_marshalled(file, data)
  remote = load_marshalled(file, download_remote("http://rubygems.org/#{file}", file))
  puts "remote=#{remote.type}"
  puts "local=#{local.type}"
  puts "remote  #{remote.first.inspect} local #{local.first.inspect}"
  if filename.include?("Marshal.4.8")
    local.each do |full_name, gem|
      remote += [full_name, gem]
    end

  else
    remote += local
  end

  marshal_to_file(remote, "#{DIR}/general/#{file}")

end
