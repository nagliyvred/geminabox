require 'test_helper'
require 'minitest/unit'
require 'rack/test'
require 'mocha'


class ProxyTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def setup
    Geminabox.enable_proxy_cache = true
    clean_data_dir
    real_file_path = File.join(Geminabox.general_data, "gems/real_file.gem")
    dir = File.dirname(real_file_path)
    FileUtils.mkdir_p(dir) unless File.exists?(dir)
    File.open(real_file_path, 'w') { |f| f.write("some real data") } 
  end

  def teardown
    FileUtils.rm(File.join(Geminabox.general_data, "gems/real_file.gem"))
  end

  def app
    Geminabox
  end

  test "repo returns a file from the underlying repository if it is not found locally" do
    stub_request(:get, SOME_REPO + "/gems/existing.gem").to_return(:status => 200, :body => "this is a gem's content")
    get "/gems/existing.gem"
    assert last_response.body.size > 0
    assert last_response.status == 200, last_response.errors
    assert_equal last_response.body, "this is a gem's content"
  end


  test "repo returns 404 if file is not there and can't be found remotely" do
    
    stub_request(:get, SOME_REPO + "/gems/missing.gem").to_return(:status => 404, :body => "not found")
    get "/missing.gem"
    assert last_response.status == 404, "expected 404, found #{last_response.status}"
    
  end

  test "repo returns a file if it is present on the server" do 
    get "/gems/real_file.gem"
    assert last_response.ok?, last_response.errors
  end
end
