require 'test_helper'
require 'mocha'

class SpecMergerTest < MiniTest::Unit::TestCase
    DIR = "/tmp/geminabox-merger-test"
    LOCAL_SPEC = [
        ["access_schema", Gem::Version.new("0.6.1"), "ruby"],
        ["acclaim", Gem::Version.new("0.5.1"), "ruby"],
        ["accountable", Gem::Version.new("0.0.2"), "ruby"],
    ]
    REMOTE_SPEC = [
        ["accountancy", Gem::Version.new("0.0.1"), "ruby"],
        ["accounts", Gem::Version.new("0.0.1"), "ruby"],
        ["account_scopper", Gem::Version.new("0.2.0"), "ruby"],
        ["accumulators", Gem::Version.new("0.5.1"), "ruby"],
        ["acdc", Gem::Version.new("0.7.7"), "ruby"]
    ] 

    def test_merger
        url = "http://something.com"
        file_name = "latest_specs.4.8.gz"

        stub_request(:get, url + "/#{file_name}").to_return(:status => 200, :body => Gem.gzip(Marshal.dump(LOCAL_SPEC)))

        File.expects(:open).with(fixture("latest_specs.4.8.gz")).returns(Gem.gzip(Marshal.dump(REMOTE_SPEC)))

        merger = Geminabox::Merger.new( url, fixture("latest_specs.4.8.gz")) 
        result = merger.merge
        refute_nil result 

        assert result.select { |el| el.first == "access_schema" }.size == 1
        assert result.select { |el| el.first == "acdc" }.size == 1

        
    end

    def setup 
        FileUtils.mkdir(DIR)
    end

    def teardown
        FileUtils.rm_rf(DIR)
    end
end
