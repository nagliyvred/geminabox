require 'rubygems'
require 'httpclient'
require 'geminabox'

module GeminaboxTools
  def self.download_data(url)
    client = HTTPClient.new
    response = client.get(url, :follow_redirect => true)
    fail "failed to download #{url}: #{response.status}" unless response.status == 200
    response.content
  end

end

class SpecMerge 


FILES = [ 'latest_specs.4.8.gz', 
          'prerelease_specs.4.8.gz', 
          'specs.4.8.gz',
          'Marshal.4.8.Z']


  def run_merge

    FILES.each do |file|

      Geminabox.repos.each do |repo|
        puts "merging #{file}"
        filename = File.join(Geminabox.local_data, file)
        merger = Merger.new(repo, filename) 
        result = merger.merge
        merger.marshal_to_file(Geminabox.general_data + file, result)
      end

    end
  end
end


class Merger

  def initialize(repo, filename)
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

