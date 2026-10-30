require "test_helper"

class Platforms::Linkedin::UploadsImageTest < ActiveSupport::TestCase
  UPLOAD_URL = "https://www.linkedin.com/dms-uploads/sp/v2/image-1"

  def setup
    @subject = Platforms::Linkedin::UploadsImage.new
  end

  def test_puts_the_bytes_with_their_own_content_type
    upload = stub_request(:put, UPLOAD_URL)
      .with(body: "GIF89a", headers: {"Authorization" => "Bearer token", "Content-Type" => "image/gif"})
      .to_return(status: 201)

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert outcome.success?
    assert_requested upload
  end

  def test_reports_an_upload_linkedin_rejects
    stub_request(:put, UPLOAD_URL).to_return(status: 400, body: "Bad image")

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert_equal "Failed to upload image to LinkedIn. Response: Bad image", outcome.message
  end

  def test_reports_a_connection_error
    stub_request(:put, UPLOAD_URL).to_timeout

    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "token")

    assert_match(/\AFailed to upload image to LinkedIn: /, outcome.message)
  end

  def test_an_error_building_the_upload_does_not_repeat_the_access_token
    outcome = @subject.upload_bytes("GIF89a", content_type: "image/gif", upload_url: UPLOAD_URL, access_token: "a warning\nSECRET-TOKEN-123")

    assert_match(/\AFailed to upload image to LinkedIn: /, outcome.message)
    assert_not_includes outcome.message, "SECRET-TOKEN-123"
  end
end
