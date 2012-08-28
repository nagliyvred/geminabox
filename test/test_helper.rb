require "rubygems"
gem "bundler"
require "bundler/setup"

require 'geminabox'
require 'minitest/autorun'
require 'fileutils'
require 'test_support/gem_factory'
require 'test_support/geminabox_test_case'
require 'webmock/minitest'



module TestMethodMagic
  def test(test_name, &block)
    WebMock.allow_net_connect!
    define_method "test: #{test_name} ", &block
  end
end


class MiniTest::Unit::TestCase
  extend TestMethodMagic

  WebMock.allow_net_connect!


  TEST_DATA_DIR="/tmp/geminabox-test-data"
  SOME_REPO = "www.whateverrepo.org"
  def clean_data_dir
    FileUtils.rm_rf(TEST_DATA_DIR)
    FileUtils.mkdir(TEST_DATA_DIR)
    Geminabox.data = TEST_DATA_DIR
    Geminabox.local_data = TEST_DATA_DIR + "/local"
    Geminabox.general_data = TEST_DATA_DIR + '/general'
    FileUtils.mkdir_p(Geminabox.local_data)
    FileUtils.mkdir_p(Geminabox.general_data)
    Geminabox.repos = [SOME_REPO] 
  end

  def self.fixture(path)
    File.join(File.expand_path("../fixtures", __FILE__), path)
  end

  def fixture(*args)
    self.class.fixture(*args)
  end


  def silence_stream(stream)
    old_stream = stream.dup
    stream.reopen('/dev/null')
    stream.sync = true
    yield
  ensure
    stream.reopen(old_stream)
  end

  def silence
    silence_stream(STDERR) do
      silence_stream(STDOUT) do
        yield
      end
    end
  end

  def inject_gems(&block)
    silence do
      yield GemFactory.new(File.join(Geminabox.local_data, "gems"))
      Gem::Indexer.new(Geminabox.local_data).generate_index
    end
  end

end

