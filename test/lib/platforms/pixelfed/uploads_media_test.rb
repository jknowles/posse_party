require "test_helper"

class Platforms::Pixelfed::UploadsMediaTest < ActiveSupport::TestCase
  def test_uploads_image_and_returns_media_id
    image_url = "https://example.com/photo.jpg"
    stub_request(:get, image_url)
      .to_return(status: 200, headers: {"Content-Type" => "image/jpeg"}, body: "fake-image-bytes")
    upload_stub = stub_request(:post, "https://pixelfed.social/api/v1/media")
      .with(headers: {"Authorization" => "Bearer SOME_TOKEN"})
      .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: {id: "42"}.to_json)

    media_id = Platforms::Pixelfed::UploadsMedia.new.upload(
      image_url, base_url: "https://pixelfed.social", access_token: "SOME_TOKEN"
    )

    assert_equal "42", media_id
    assert_requested upload_stub
    assert_requested(:post, "https://pixelfed.social/api/v1/media") do |request|
      request.body.include?('name="file"')
    end
  end

  def test_raises_when_image_cannot_be_downloaded
    image_url = "https://example.com/missing.jpg"
    stub_request(:get, image_url).to_return(status: 404)

    error = assert_raises(RuntimeError) do
      Platforms::Pixelfed::UploadsMedia.new.upload(
        image_url, base_url: "https://pixelfed.social", access_token: "SOME_TOKEN"
      )
    end
    assert_match(/Failed to download Pixelfed media/, error.message)
  end

  def test_raises_when_upload_fails
    image_url = "https://example.com/photo.jpg"
    stub_request(:get, image_url)
      .to_return(status: 200, headers: {"Content-Type" => "image/jpeg"}, body: "fake-image-bytes")
    stub_request(:post, "https://pixelfed.social/api/v1/media")
      .to_return(status: 422, body: "Unprocessable")

    error = assert_raises(RuntimeError) do
      Platforms::Pixelfed::UploadsMedia.new.upload(
        image_url, base_url: "https://pixelfed.social", access_token: "SOME_TOKEN"
      )
    end
    assert_match(/Failed to upload media to Pixelfed/, error.message)
  end
end
