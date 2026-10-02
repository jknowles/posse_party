require "test_helper"

class Platforms::Mastodon::CallsMastodonMediaApiTest < ActiveSupport::TestCase
  def setup
    @subject = Platforms::Mastodon::CallsMastodonMediaApi.new
    @account = Account.new(platform_tag: "mastodon", credentials: {"base_url" => "https://mastodon.example", "access_token" => "token"})
  end

  def test_uploads_the_file_with_its_description_and_reports_it_ready
    upload = stub_request(:post, "https://mastodon.example/api/v2/media")
      .with(headers: {"Authorization" => "Bearer token"}) { |request|
        request.headers["Content-Type"].start_with?("multipart/form-data") &&
          request.body.match?(/name="file"; filename="media[^"]*\.png"/) &&
          request.body.include?("Content-Type: image/png\r\n\r\nPNG") &&
          request.body.include?(%(name="description"\r\n\r\nA navy square))
      }
      .to_return(status: 200, body: {id: "110", url: "https://files.mastodon.example/110.png"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "PNG", extension: ".png", description: "A navy square")

    assert result.success?
    assert_equal Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id: "110", ready?: true), result.data
    assert_requested upload
  end

  def test_an_upload_mastodon_is_still_processing_is_not_ready
    stub_request(:post, "https://mastodon.example/api/v2/media")
      .to_return(status: 202, body: {id: "111", url: nil}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "GIF89a", extension: ".gif", description: "A loop")

    assert_equal Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id: "111", ready?: false), result.data
  end

  def test_leaves_out_a_blank_description
    upload = stub_request(:post, "https://mastodon.example/api/v2/media")
      .with { |request| !request.body.include?(%(name="description")) }
      .to_return(status: 200, body: {id: "112"}.to_json, headers: {"Content-Type" => "application/json"})

    @subject.upload(@account, bytes: "PNG", extension: ".png", description: "")

    assert_requested upload
  end

  def test_reports_an_upload_mastodon_refuses
    stub_request(:post, "https://mastodon.example/api/v2/media")
      .to_return(status: 422, body: {error: "File type of uploaded media could not be verified"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@account, bytes: "RIFF", extension: ".webp", description: "")

    assert result.failure?
    assert_equal %(Mastodon refused the upload (HTTP 422): {"error":"File type of uploaded media could not be verified"}), result.error
  end

  def test_checks_media_that_has_finished_processing
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .with(headers: {"Authorization" => "Bearer token"})
      .to_return(status: 200, body: {id: "111", url: "https://files.mastodon.example/111.mp4"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.check(@account, "111")

    assert result.success?
    assert_equal true, result.data
  end

  def test_checks_media_that_is_still_processing
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .to_return(status: 206, body: {id: "111", url: nil}.to_json, headers: {"Content-Type" => "application/json"})

    assert_equal false, @subject.check(@account, "111").data
  end

  def test_reports_media_mastodon_could_not_process
    stub_request(:get, "https://mastodon.example/api/v1/media/111")
      .to_return(status: 422, body: {error: "Error processing thumbnail for uploaded media"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.check(@account, "111")

    assert result.failure?
    assert_equal %(Mastodon could not process media 111 (HTTP 422): {"error":"Error processing thumbnail for uploaded media"}), result.error
  end
end
