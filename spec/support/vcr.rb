require 'vcr'

VCR.configure do |config|
  config.default_cassette_options = {
    decode_compressed_response: true
  }
  config.cassette_library_dir = File.join(
    File.dirname(__FILE__), '..', 'fixtures', 'vcr_cassettes'
  )
  config.hook_into :webmock
  config.filter_sensitive_data('<RAPID_API_KEY>') {
    ENV.fetch('RAPID_API_KEY', 'hidden')
  }
end
