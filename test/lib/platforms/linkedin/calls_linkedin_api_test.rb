require "test_helper"

class Platforms::Linkedin::CallsLinkedinApiTest < ActiveSupport::TestCase
  def test_a_failed_call_does_not_repeat_the_access_token
    stub_request(:post, "https://api.linkedin.com/rest/images?action=initializeUpload").to_return(status: 429, body: "Too Many Requests")

    result = Platforms::Linkedin::CallsLinkedinApi.new.call(method: :post, path: "rest/images?action=initializeUpload", access_token: "SECRET-TOKEN-123", body: {initializeUploadRequest: {owner: "urn:li:person:1"}})

    assert_not result.success?
    assert_includes result.message, "Too Many Requests"
    assert_not_includes result.message, "SECRET-TOKEN-123"
  end
end
