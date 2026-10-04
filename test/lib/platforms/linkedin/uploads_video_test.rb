require "test_helper"

class Platforms::Linkedin::UploadsVideoTest < ActiveSupport::TestCase
  API = "https://api.linkedin.com/rest/videos"
  VIDEO_URN = "urn:li:video:C5F10AQ"
  PART_1 = "https://www.linkedin.com/dms-uploads/part-1"
  PART_2 = "https://www.linkedin.com/dms-uploads/part-2"
  THUMBNAIL = "https://www.linkedin.com/dms-uploads/thumbnail"

  def setup
    @subject = Platforms::Linkedin::UploadsVideo.new
    @path = file_fixture("media/loop.mp4").to_s
    @bytes = file_fixture("media/loop.mp4").binread
  end

  def test_uploads_each_part_and_finalizes_with_their_etags_in_order
    stub_initialize(upload_thumbnail: false, instructions: [
      {uploadUrl: PART_1, firstByte: 0, lastByte: 99_999},
      {uploadUrl: PART_2, firstByte: 100_000, lastByte: @bytes.bytesize - 1}
    ])
    part_1 = stub_part(PART_1, @bytes.byteslice(0, 100_000), etag: %("etag-1"))
    part_2 = stub_part(PART_2, @bytes.byteslice(100_000..), etag: %("etag-2"))
    finalize = stub_finalize(["etag-1", "etag-2"])

    result = @subject.upload(@path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1")

    assert result.success?
    assert_equal VIDEO_URN, result.data
    assert_requested part_1
    assert_requested part_2
    assert_requested finalize
  end

  def test_uploads_the_thumbnail_it_is_given
    stub_initialize(upload_thumbnail: true, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}], thumbnailUploadUrl: THUMBNAIL)
    stub_part(PART_1, @bytes, etag: "etag-1")
    thumbnail = stub_request(:put, THUMBNAIL)
      .with(body: "JPG", headers: {"Authorization" => "Bearer token", "media-type-family" => "STILLIMAGE", "Content-Type" => "application/octet-stream"})
      .to_return(status: 201)
    stub_finalize(["etag-1"])

    result = @subject.upload(@path, thumbnail: "JPG", access_token: "token", person_urn: "urn:li:person:1")

    assert_equal VIDEO_URN, result.data
    assert_requested thumbnail
  end

  def test_reports_an_upload_linkedin_will_not_start
    stub_request(:post, "#{API}?action=initializeUpload").to_return(status: 422, body: {message: "Video too short"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.upload(@path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1")

    assert result.failure?
    assert_match(/\ALinkedIn would not start the video upload\. Error calling LinkedIn API\..*Video too short/m, result.error)
  end

  def test_reports_a_part_linkedin_refuses
    stub_initialize(upload_thumbnail: false, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}])
    stub_request(:put, PART_1).to_return(status: 400, body: "Bad part")

    result = @subject.upload(@path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1")

    assert_equal "LinkedIn refused a video upload (HTTP 400): Bad part", result.error
    assert_not_requested :post, "#{API}?action=finalizeUpload"
  end

  def test_reports_a_thumbnail_linkedin_refuses
    stub_initialize(upload_thumbnail: true, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}], thumbnailUploadUrl: THUMBNAIL)
    stub_part(PART_1, @bytes, etag: "etag-1")
    stub_request(:put, THUMBNAIL).to_return(status: 400, body: "Bad thumbnail")

    result = @subject.upload(@path, thumbnail: "JPG", access_token: "token", person_urn: "urn:li:person:1")

    assert_equal "LinkedIn refused a video upload (HTTP 400): Bad thumbnail", result.error
    assert_not_requested :post, "#{API}?action=finalizeUpload"
  end

  def test_reports_a_missing_thumbnail_upload_url
    stub_initialize(upload_thumbnail: true, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}])
    stub_part(PART_1, @bytes, etag: "etag-1")

    result = @subject.upload(@path, thumbnail: "JPG", access_token: "token", person_urn: "urn:li:person:1")

    assert_equal "LinkedIn gave no thumbnail upload URL", result.error
    assert_not_requested :post, "#{API}?action=finalizeUpload"
  end

  def test_reports_a_part_that_comes_back_without_an_etag
    stub_initialize(upload_thumbnail: false, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}])
    stub_request(:put, PART_1).to_return(status: 200)

    result = @subject.upload(@path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1")

    assert_equal "LinkedIn returned no ETag for a video part", result.error
    assert_not_requested :post, "#{API}?action=finalizeUpload"
  end

  def test_a_failed_part_does_not_repeat_the_access_token
    stub_initialize(upload_thumbnail: false, instructions: [{uploadUrl: PART_1, firstByte: 0, lastByte: @bytes.bytesize - 1}])
    stub_request(:put, PART_1).to_raise(ArgumentError.new(%(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)))

    result = @subject.upload(@path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1")

    assert_equal %(Could not upload video to LinkedIn: header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF), result.error
  end

  def test_reports_a_videos_status
    stub_request(:get, "#{API}/urn%3Ali%3Avideo%3AC5F10AQ")
      .with(headers: {"Authorization" => "Bearer token", "LinkedIn-Version" => "202605"})
      .to_return(status: 200, body: {id: VIDEO_URN, status: "PROCESSING"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.status(VIDEO_URN, access_token: "token")

    assert_equal "PROCESSING", result.data
  end

  def test_reports_a_status_linkedin_will_not_give
    stub_request(:get, "#{API}/urn%3Ali%3Avideo%3AC5F10AQ").to_return(status: 404, body: {message: "Not found"}.to_json, headers: {"Content-Type" => "application/json"})

    result = @subject.status(VIDEO_URN, access_token: "token")

    assert_match(/\ALinkedIn could not report on video urn:li:video:C5F10AQ\. /, result.error)
  end

  private

  def stub_initialize(upload_thumbnail:, instructions:, **extra)
    stub_request(:post, "#{API}?action=initializeUpload")
      .with(headers: {"Authorization" => "Bearer token"}, body: {
        initializeUploadRequest: {owner: "urn:li:person:1", fileSizeBytes: @bytes.bytesize, uploadCaptions: false, uploadThumbnail: upload_thumbnail}
      }.to_json)
      .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: {
        value: {video: VIDEO_URN, uploadInstructions: instructions, uploadToken: "", **extra}
      }.to_json)
  end

  def stub_part(url, bytes, etag:)
    stub_request(:put, url)
      .with(body: bytes, headers: {"Content-Type" => "application/octet-stream"})
      .to_return(status: 200, headers: {"ETag" => etag})
  end

  def stub_finalize(part_ids)
    stub_request(:post, "#{API}?action=finalizeUpload")
      .with(body: {finalizeUploadRequest: {video: VIDEO_URN, uploadToken: "", uploadedPartIds: part_ids}}.to_json)
      .to_return(status: 200)
  end
end
