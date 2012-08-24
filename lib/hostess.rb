require 'sinatra/base'
require 'httpclient'

class Hostess < Sinatra::Base
  configure do
    enable :logging
  end

  before do
    logger.level = Logger::INFO
  end
 
  def initialize(param)
    super(param)
    %w[local general].each do |path|
      FileUtils.mkdir_p(local_file(path + '/quick/Marshal.4.8'))
      FileUtils.mkdir_p(local_file(path + "/gems"))
    end

  end

  def serve_local
    serve('/local' + request.path_info)
  end

  def serve_general
    serve('/general' + request.path_info)
  end

  def serve_any
    if is_local?(request.path_info)
      serve_local
    else 
      serve_general
    end
  end

  def serve(path)
    logger.info "serve #{path}"
    unless local_file_exists?(path)
      Geminabox.repos.each do |repo|
        break if pull_remote_file(repo, path, Geminabox.data)
      end
    end

    send_file(local_file(path), :type => response['Content-Type'])
  end

  def is_local?(gemname)
    File.exists?(File.join(Geminabox.local_data, gemname))
  end

  def local_file(gemname)
    File.expand_path(File.join(Geminabox.data, gemname))
  end

  def local_file_exists?(gemname)
      logger.info "checking existence of #{gemname} #{local_file(gemname)}"
      File.exists?(local_file(gemname))
  end

  def pull_remote_file(repo, file_path, path)
    logger.info "pulling file #{file_path} from the repo #{repo} and putting it to #{path}"
    url = repo + file_path.sub('/local','').sub('/general','')
    download(url, local_file(file_path))
  end

  def download(url, filename)
    http_client = HTTPClient.new
    response = http_client.get(url, :follow_redirect => true)
    logger.info "downloading #{url} #{response.status}"
    if response.status == 200 
      File.open(filename, "wb") { |f| f.write(response.content) }
      logger.info "saved file #{filename}"
      return true
    end
    return false
  end


  %w[/specs.4.8.gz
     /latest_specs.4.8.gz
     /prerelease_specs.4.8.gz
  ].each do |index|
    get index do
      content_type('application/x-gzip')
      serve_general
    end
  end

  %w[/quick/Marshal.4.8/*.gemspec.rz
     /yaml.Z
     /Marshal.4.8.Z
  ].each do |deflated_index|
    get deflated_index do
      content_type('application/x-deflate')
      serve_any
    end
  end

  %w[/yaml
     /Marshal.4.8
     /specs.4.8
     /latest_specs.4.8
     /prerelease_specs.4.8
  ].each do |old_index|
    get old_index do
      serve_general
    end
  end

  get "/gems/*.gem" do
    serve_any
  end
end
