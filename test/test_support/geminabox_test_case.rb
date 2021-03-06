require 'minitest/unit'
require 'timeout'
require 'socket'
require 'rack'
require 'uri'
require 'fileutils'
require 'tempfile'
require 'webrick'
require 'webrick/https'
require 'logger'
require 'rack/auth/abstract/handler'
require 'rack/auth/abstract/request'

class Geminabox::TestCase < MiniTest::Unit::TestCase
  class << self
    # DSL
    def url(url = nil)
      @url ||= url || "http://localhost/"
    end

    def ssl(ssl = nil)
      if ssl.nil?
        @ssl
      else
        @ssl = ssl
      end
    end

    def data(data = nil)
      @data ||= data || "/tmp/geminabox-test-data/"
    end

    def app(&block)
      @app = block || @app || lambda{|builder| run Geminabox }
    end

    def to_app
      Rack::Builder.app(&app)
    end

    def should_push_gem(gemname = :example, *args)
      test("can push #{gemname}") do
        assert_can_push(gemname, *args)
        assert File.exists?( File.join(config.data, "local", "gems", File.basename(gem_file(gemname, *args)) ) ), "Gemfile not in data dir."
      end
    end


    def url_with_port(port)
      uri = URI.parse url
      uri.port = port
      uri.to_s
    end

  end

  def setup
    super
    start_app!
  end

  def teardown
    stop_app!
    super
  end



  def config
    self.class
  end

  def url_for(path)
    @url_with_port ||= config.url_with_port(@test_server_port).gsub(%r{/$}, "")
    path = "/#{path}" unless path.start_with? "/"
    @url_with_port + path
  end

  FAKE_HOME = "/tmp/geminabox-test-home"
  def self.setup_fake_home!
    return if @setup_fake_home
    @setup_fake_home = true
    FileUtils.rm_rf(FAKE_HOME)
    FileUtils.mkdir_p("#{FAKE_HOME}/gems")
    FileUtils.mkdir_p("#{FAKE_HOME}/specifications")

    FileUtils.ln_s(fixture("geminabox-9999.0.0.gemspec"), "#{FAKE_HOME}/specifications/geminabox-9999.0.0.gemspec")
    FileUtils.ln_s(fixture("../.."), "#{FAKE_HOME}/gems/geminabox-9999.0.0.gem")
  end

  def geminabox_push(gemfile)
    Geminabox::TestCase.setup_fake_home!
    command = "GEM_HOME=#{FAKE_HOME} gem inabox #{gemfile} -g '#{config.url_with_port(@test_server_port)}' 2>&1"
    output = ""
    IO.popen(command, "r") do |io|
      data = io.read
      output << data
    end
    output
  end

  def assert_can_push(gemname = :example, *args)
    assert_match( /Gem .* received and indexed./, geminabox_push(gem_file(gemname, *args)))
  end

  def find_free_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end


  def start_app!
    clean_data_dir
    @test_server_port = find_free_port
    server_options = {
      :app => config.to_app,
      :Port => @test_server_port,
      :AccessLog => [],
      :Logger => WEBrick::Log::new("/dev/null", 7)
    }
    
    if config.ssl
      server_options.merge!(
        :SSLEnable => true,
        :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
        :SSLPrivateKey => OpenSSL::PKey::RSA.new(File.read(fixture("127.0.0.1.key"))),
        :SSLCertificate => OpenSSL::X509::Certificate.new(File.read(fixture("127.0.0.1.crt"))),
        :SSLCertName => [["CN", "127.0.0.1"]]
      )
    end


    @app_server = fork do
      begin
        Geminabox.data = File.expand_path(File.join(config.data))
        $stderr.reopen("/tmp/err")
        $stdout.reopen("/tmp/out")
        Rack::Server.start(server_options)
      ensure
        exit
      end
    end

    Timeout.timeout(10) do
      begin
        Timeout.timeout(1) do
          TCPSocket.open("127.0.0.1", @test_server_port).close
        end
      rescue Errno::ECONNREFUSED
        sleep 0.05
        retry
      end
    end  
  end

  def stop_app!
    Process.kill(9, @app_server) if @app_server
  end

  def gem_file(*args)
    GemFactory.gem_file(*args)
  end

end


