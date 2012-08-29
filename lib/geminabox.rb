require 'rubygems'
require 'digest/md5'
require 'builder'
require 'sinatra/base'
require 'rubygems/builder'
require 'rubygems/indexer'
require 'hostess'
require 'geminabox/version'
require 'rss/atom'
require 'rufus/scheduler'

class Geminabox < Sinatra::Base
  configure do
    enable :logging
  end

  enable :static, :methodoverride

  set :enable_proxy_cache, false
  set :repos, "http://rubygems.org"
  set :public_folder, File.join(File.dirname(__FILE__), *%w[.. public])
  set :data, File.join(File.dirname(__FILE__), *%w[.. data])
  set :build_legacy, false
  set :incremental_updates, false
  set :views, File.join(File.dirname(__FILE__), *%w[.. views])
  set :allow_replace, false
  set :logging, true
  set :dump_errors, true
  set :synchronize_schedule, "0 1 * * *"
  use Hostess

  scheduler = Rufus::Scheduler.start_new

  scheduler.cron settings.synchronize_schedule do
    puts 'synchronising spec files from the underlying repositories....'
    sync_specs
    puts 'spec files updated'
  end
    

  def self.local_data
    File.join(settings.data, 'local')
  end

  def self.general_data
    File.join(settings.data, 'general')
  end


  class << self
    def disallow_replace?
      ! allow_replace
    end

    def fixup_bundler_rubygems!
      return if @post_reset_hook_applied
      Gem.post_reset{ Gem::Specification.all = nil } if defined? Bundler and Gem.respond_to? :post_reset
      @post_reset_hook_applied = true
    end
  end

  autoload :GemVersionCollection, "geminabox/gem_version_collection"
  autoload :DiskCache, "geminabox/disk_cache"
  autoload :SpecMerge, "geminabox/spec_merge.rb"

  before do
    headers 'X-Powered-By' => "geminabox #{GeminaboxVersion}"
  end

  get '/' do
    @gems = load_gems
    @index_gems = index_gems(@gems)
    erb :index
  end

  get '/atom.xml' do
    @gems = load_gems
    erb :atom, :layout => false
  end


  def calculate_dependencies(gem)
    spec = spec_for(gem.name, gem.number)
    {
      :name => gem.name,
      :number => gem.number.version,
      :platform => gem.platform,
      :dependencies => spec.dependencies.select {|dep| dep.type == :runtime}.map {|dep| [dep.name, dep.requirement.to_s] }
    }
  end

  get '/api/v1/dependencies' do
    query_gems = params[:gems].split(',').sort
    disk_cache.cache(params[:gems]) do
      local_gems = load_gems.gems
      deps = local_gems.select {|gem| query_gems.include?(gem.name) }.map do |gem|
        query_gems.delete(gem.name)
        calculate_dependencies(gem)
      end
      ext_deps = resolve_external(query_gems)
      Marshal.dump(deps + ext_deps)
    end
  end
  


  def resolve_external(list)
    return [] unless Geminabox.enable_proxy_cache

    client = HTTPClient.new
    data = nil
    response = nil
    settings.repos.each do |repo|
      url = "#{repo}/api/v1/dependencies?gems=#{list.join(',')}"
      env['rack.logger'].info "proxying call to #{url}"
      response = client.get(url, :follow_redirect => true)
      data = Marshal.load(response.content) if response.status == 200
    end
    response.content ? response.content : "no response content"
    error_response(500, "Failed to contact underlying server: #{response.content ? response.content : "no response content" }" ) if data == nil 
    data
  end

  get '/upload' do
    erb :upload
  end

  get '/reindex' do
    reindex(:force_rebuild)
    redirect url("/")
  end

  get '/sync_specs' do
    sync_specs
    redirect url('/')
  end

  delete '/gems/*.gem' do
    File.delete file_path if File.exists? file_path
    reindex(:force_rebuild)
    redirect url("/")
  end

  post '/upload' do
    if File.exists? Geminabox.data
      error_response( 500, "Please ensure #{File.expand_path(Geminabox.data)} is a directory." ) unless File.directory? Geminabox.data
    end
    if File.exists? Geminabox.local_data
      error_response( 500, "Please ensure #{File.expand_path(Geminabox.local_data)} is a directory." ) unless File.directory? Geminabox.local_data
      error_response( 500, "Please ensure #{File.expand_path(Geminabox.local_data)} is writable by the geminabox web server." ) unless File.writable? Geminabox.local_data
    else
      begin
        FileUtils.mkdir_p(Geminabox.local_data)
      rescue Errno::EACCES, Errno::ENOENT, RuntimeError => e
        error_response( 500, "Could not create #{File.expand_path(Geminabox.local_data)}.\n#{e}\n#{e.message}" )
      end
    end

    unless params[:file] && (tmpfile = params[:file][:tempfile]) && (name = params[:file][:filename])
      @error = "No file selected"
      halt [400, erb(:upload)]
    end

    FileUtils.mkdir_p(File.join(Geminabox.local_data, "gems"))

    tmpfile.binmode

    gem_name = File.basename(name)
    dest_filename = File.join(Geminabox.local_data, "gems", gem_name)

    if Geminabox.disallow_replace? and File.exist?(dest_filename)
      existing_file_digest = Digest::SHA1.file(dest_filename).hexdigest
      tmpfile_digest = Digest::SHA1.file(tmpfile.path).hexdigest

      if existing_file_digest != tmpfile_digest
        error_response(409, "Updating an existing gem is not permitted.\nYou should either delete the existing version, or change your version number.")
      else
        error_response(200, "Ignoring upload, you uploaded the same thing previously.")
      end
    end

    File.open(dest_filename, "wb") do |f|
      while blk = tmpfile.read(65536)
        f << blk
      end
    end
    reindex

    if api_request?
      "Gem #{gem_name} received and indexed."
    else
      redirect url("/")
    end
  end

private

  def api_request?
    request.accept.first == "text/plain"
  end

  def error_response(code, message)
    halt [code, message] if api_request?
    html = <<HTML
<html>
  <head><title>Error - #{code}</title></head>
  <body>
    <h1>Error - #{code}</h1>
    <p>#{message}</p>
  </body>
</html>
HTML
    halt [code, html]
  end

  def reindex(force_rebuild = false)
    Geminabox.fixup_bundler_rubygems!
    force_rebuild = true unless settings.incremental_updates
    if force_rebuild
      indexer.generate_index
    else
      begin
        indexer.update_index
      rescue => e
        logger.info "#{e.class}:#{e.message}"
        logger.info e.backtrace.join("\n")
        reindex(:force_rebuild)
      end
    end
    disk_cache.flush
  end

  def indexer
    Gem::Indexer.new(Geminabox.local_data, :build_legacy => settings.build_legacy)
  end

  def file_path
    File.expand_path(File.join(settings.data, *request.path_info))
  end

  def disk_cache
    @disk_cache = Geminabox::DiskCache.new(File.join(settings.data, "_cache"))
  end

  def load_gems
    @loaded_gems ||=
      %w(specs prerelease_specs).inject(GemVersionCollection.new){|gems, specs_file_type|
        specs_file_path = File.join(Geminabox.local_data, "#{specs_file_type}.#{Gem.marshal_version}.gz")
        if File.exists?(specs_file_path)
          gems |= Geminabox::GemVersionCollection.new(Marshal.load(Gem.gunzip(Gem.read_binary(specs_file_path))))
        end
        gems
      }
  end

  def index_gems(gems)
    Set.new(gems.map{|gem| gem.name[0..0].downcase})
  end

  def self.sync_specs
    SpecMerge.new().run_merge()
  end

  helpers do
    def spec_for(gem_name, version)
      spec_file = File.join(Geminabox.local_data, "quick", "Marshal.#{Gem.marshal_version}", "#{gem_name}-#{version}.gemspec.rz")
      Marshal.load(Gem.inflate(File.read(spec_file))) if File.exists? spec_file
    end
  end
end
