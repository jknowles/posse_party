require "test_helper"

class Platforms::Linkedin::CallsLinkedinApiTest < ActiveSupport::TestCase
  def test_a_failed_call_does_not_repeat_the_access_token
    stub_request(:post, "https://api.linkedin.com/rest/images?action=initializeUpload").to_return(status: 429, body: "Too Many Requests")

    result = Platforms::Linkedin::CallsLinkedinApi.new.call(method: :post, path: "rest/images?action=initializeUpload", access_token: "SECRET-TOKEN-123", body: {initializeUploadRequest: {owner: "urn:li:person:1"}})

    assert_not result.success?
    assert_includes result.message, "Too Many Requests"
    assert_not_includes result.message, "SECRET-TOKEN-123"
  end

  def test_an_error_building_the_request_does_not_repeat_the_access_token
    result = Platforms::Linkedin::CallsLinkedinApi.new.call(method: :post, path: "rest/posts", access_token: "a warning\nSECRET-TOKEN-123", body: {commentary: "A map"})

    assert_not result.success?
    assert_includes result.message, "Unexpected error calling LinkedIn API"
    assert_not_includes result.message, "SECRET-TOKEN-123"
  end

  def test_an_error_building_the_request_does_not_repeat_a_token_captured_after_a_quote
    result = Platforms::Linkedin::CallsLinkedinApi.new.call(method: :post, path: "rest/posts", access_token: %(warn "x"\nSECRET-TOKEN-123), body: {commentary: "A map"})

    assert_not result.success?
    assert_not_includes result.message, "SECRET-TOKEN-123"
  end
end
