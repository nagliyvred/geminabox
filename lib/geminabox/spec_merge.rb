require 'rubygems'
require 'httpclient'
require 'geminabox'

module GeminaboxTools
  def self.download_data(url)
    client = HTTPClient.new
    response = client.get(url, :follow_redirect => true)
    puts "response code is #{response.status}"
    response.content
  end

end

class SpecMerge 


FILES = [ 'latest_specs.4.8.gz', 
          'prerelease_specs.4.8.gz', 
          'specs.4.8.gz',
          'Marshal.4.8.Z']

REPOS = [ "http://rubygems.org"]

  def run_merge

    FILES.each do |file|

      REPOS.each do |repo|
        puts "handling #{file}"
        filename = Geminabox.local_data + file
        puts "filename=#{filename}"
        merger = Merger.new(repo, filename) 
        result = merger.merge
        merger.marshal_to_file(Geminabox.general_data + file, result)
      end

    end
  end

  


end


class Merger

  def initialize(repo, filename)
    puts filename.split("/").last
    @filename = filename
    @local_data = File.open(filename) { |f| f.read }
    @remote_data = GeminaboxTools::download_data("#{repo}/#{filename.split("/").last}" )
  end


  def unpack(data)
    if @filename.end_with?('gz')
      Gem.gunzip(data)
    else
      Gem.inflate(data)
    end
  end

  def pack(data)
    if @filename.end_with?("gz")
      Gem.gzip(data)
    else 
      Gem.deflate(data)
    end
  end

 
  def load_marshalled(data)
    Marshal.load(unpack(data))
  end

    def marshal_to_file(file_to_save,data)
    File.open(file_to_save, 'wb') { |f| f.write(pack(Marshal.dump(data))) }
  end


  def merge
    local = load_marshalled(@local_data)
    remote = load_marshalled(@remote_data)
    puts "remote=#{remote.type}"
    puts "local=#{local.type}"
    puts "remote  #{remote.first.inspect} local #{local.first.inspect}"

    if @filename.include?("Marshal.4.8")
      local.each do |full_name, gem|
        remote += [full_name, gem]
      end

    else
      remote += local
    end

    remote
  end

end

TEST_DATA_DIR="/Users/tim/work/geminabox/data"
Geminabox.local_data = TEST_DATA_DIR + "/local/"
Geminabox.general_data = TEST_DATA_DIR + "/general/"
SpecMerge.new().run_merge
