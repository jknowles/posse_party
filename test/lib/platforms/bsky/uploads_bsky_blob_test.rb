require "test_helper"

class Platforms::Bsky::UploadsBskyBlobTest < ActiveSupport::TestCase
  Session = Struct.new(:pds, :access_token, :did, keyword_init: true)
  UPLOAD_URL = "https://bsky.social/xrpc/com.atproto.repo.uploadBlob"
  BLOB = {"$type" => "blob", "ref" => {"$link" => "bafkreiexample"}, "mimeType" => "image/png", "size" => 3}

  def setup
    @subject = Platforms::Bsky::UploadsBskyBlob.new
    @record_manager = Bskyrb::RecordManager.new(Session.new(pds: "https://bsky.social", access_token: "jwt"))
  end

  def test_uploads_the_bytes_with_their_content_type_and_returns_the_blob
    upload = stub_request(:post, UPLOAD_URL)
      .with(body: "PNG", headers: {"Authorization" => "Bearer jwt", "Content-Type" => "image/png"})
      .to_return(status: 200, body: {blob: BLOB}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert result.success?
    assert_equal BLOB, result.data
    assert_requested upload
  end

  def test_reports_an_upload_bluesky_refuses
    stub_request(:post, UPLOAD_URL).to_return(status: 400, body: {error: "InvalidRequest", message: "Blob too large"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert result.failure?
    assert_equal %(Bluesky refused the upload (HTTP 400): {"error":"InvalidRequest","message":"Blob too large"}), result.error
  end

  def test_reports_a_connection_error
    stub_request(:post, UPLOAD_URL).to_timeout

    result = @subject.upload("PNG", "image/png", @record_manager)

    assert_match(/\ACould not upload to Bluesky: /, result.error)
  end
end
