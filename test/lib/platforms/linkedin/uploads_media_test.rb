require "test_helper"

class Platforms::Linkedin::UploadsMediaTest < ActiveSupport::TestCase
  GIF_URL = "https://example.com/media/loop.gif"
  PNG_URL = "https://example.com/media/still.png"
  MP4_URL = "https://example.com/media/loop.mp4"
  POSTER_URL = "https://example.com/media/poster.jpg"
  VIDEO_URN = "urn:li:video:1"
  MAX_VIDEO_BYTES = 100 * 1024 * 1024

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @initiates_image_upload = Mocktail.of_next(Platforms::Linkedin::InitiatesImageUpload)
    @uploads_image = Mocktail.of_next(Platforms::Linkedin::UploadsImage)
    @uploads_video = Mocktail.of_next(Platforms::Linkedin::UploadsVideo)
    @waits_for_processing = Mocktail.of_next(WaitsForProcessing)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Linkedin::UploadsMedia.new
    @crosspost = crossposts(:admin_bsky_crosspost)
  end

  def test_uploads_each_image_and_returns_its_urn_and_alt
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("GIF89a", content_type: "image/gif", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }

    uploaded = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => GIF_URL, "alt" => "A loop"},
      {"type" => "image", "url" => PNG_URL}
    ]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [
      Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop"),
      Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "")
    ], uploaded
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    uploaded = @subject.upload(@crosspost, config(nil), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify_never_called { @downloads_media.download }
  end

  def test_uploads_a_video_and_waits_for_linkedin_to_process_it
    path = stub_video_download("video/mp4", size: 100_000)
    stub_video_upload(path, thumbnail: nil)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @uploads_video.status(VIDEO_URN, access_token: "token") }.with { Result.success("AVAILABLE") }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL, "alt" => "A loop"}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: VIDEO_URN, processing: false)], uploaded
    assert_not File.exist?(path)
    verify_never_called { @records_media_fallback.record }
  end

  def test_a_video_still_processing_when_the_wait_runs_out_is_left_to_finish
    path = stub_video_download("video/mp4", size: 100_000)
    stub_video_upload(path, thumbnail: nil)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { false }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: VIDEO_URN, processing: true)], uploaded
    verify_never_called { @records_media_fallback.record }
  end

  def test_sends_the_poster_as_the_videos_thumbnail
    path = stub_video_download("video/mp4", size: 100_000)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == POSTER_URL }, max_bytes: 20 * 1024 * 1024) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes: "JPG", content_type: "image/jpeg"))
    }
    stub_video_upload(path, thumbnail: "JPG")
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { true }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL, "poster_url" => POSTER_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [VIDEO_URN], uploaded.map(&:urn)
  end

  def test_a_poster_that_cannot_be_downloaded_leaves_linkedin_to_choose_a_frame
    path = stub_video_download("video/mp4", size: 100_000)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == POSTER_URL }, max_bytes: 20 * 1024 * 1024) }.with {
      Result.failure("Could not download #{POSTER_URL}: HTTP 404")
    }
    stub_video_upload(path, thumbnail: nil)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { true }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL, "poster_url" => POSTER_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [VIDEO_URN], uploaded.map(&:urn)
    verify_never_called { @records_media_fallback.record }
  end

  def test_a_video_linkedin_cannot_process_falls_back
    path = stub_video_download("video/mp4", size: 100_000)
    stub_video_upload(path, thumbnail: nil)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @uploads_video.status(VIDEO_URN, access_token: "token") }.with { Result.success("PROCESSING_FAILED") }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn could not process video #{VIDEO_URN}") }
  end

  def test_a_video_under_linkedins_minimum_falls_back_and_leaves_no_file
    path = stub_video_download("video/mp4", size: 1_000)

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes video of at least 76800 bytes, and #{MP4_URL} is 1000") }
    assert_not File.exist?(path)
    verify_never_called { @uploads_video.upload }
  end

  def test_a_video_that_is_not_mp4_falls_back
    stub_video_download("video/quicktime", size: 100_000)

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes MP4 video, not video/quicktime (#{MP4_URL})") }
  end

  def test_a_video_linkedin_will_not_take_falls_back_and_leaves_no_file
    path = stub_video_download("video/mp4", size: 100_000)
    stubs { @uploads_video.upload(path, thumbnail: nil, access_token: "token", person_urn: "urn:li:person:1") }.with {
      Result.failure("LinkedIn refused a video upload (HTTP 400): Bad part")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn refused a video upload (HTTP 400): Bad part") }
    assert_not File.exist?(path)
  end

  def test_a_video_beside_other_media_goes_alone_and_the_drop_is_recorded
    path = stub_video_download("video/mp4", size: 100_000)
    stub_video_upload(path, thumbnail: nil)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { true }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}, {"type" => "video", "url" => MP4_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [VIDEO_URN], uploaded.map(&:urn)
    verify { @records_media_fallback.record(@crosspost, "LinkedIn posts a video on its own; dropped 1") }
  end

  def test_finishing_reports_a_video_now_available
    stubs { @uploads_video.status(VIDEO_URN, access_token: "token") }.with { Result.success("AVAILABLE") }

    assert_equal [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: VIDEO_URN, processing: false)], @subject.finish(@crosspost, VIDEO_URN, access_token: "token")
  end

  def test_finishing_reports_a_video_still_processing
    stubs { @uploads_video.status(VIDEO_URN, access_token: "token") }.with { Result.success("PROCESSING") }

    assert_equal [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: VIDEO_URN, processing: true)], @subject.finish(@crosspost, VIDEO_URN, access_token: "token")
  end

  def test_finishing_falls_back_when_processing_failed
    stubs { @uploads_video.status(VIDEO_URN, access_token: "token") }.with { Result.success("PROCESSING_FAILED") }

    assert_equal [], @subject.finish(@crosspost, VIDEO_URN, access_token: "token")
    verify { @records_media_fallback.record(@crosspost, "LinkedIn could not process video #{VIDEO_URN}") }
  end

  def test_a_type_linkedin_does_not_take_falls_back
    stub_download(PNG_URL, "RIFF", "image/webp")

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes JPEG, PNG and GIF, not image/webp (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: 20 * 1024 * 1024) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_upload_linkedin_will_not_start_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: false, message: "Failed to initiate LinkedIn image upload.")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Failed to initiate LinkedIn image upload.") }
  end

  def test_a_rejected_upload_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with {
      Outcome.failure("Failed to upload image to LinkedIn. Response: Bad image")
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "Failed to upload image to LinkedIn. Response: Bad image") }
  end

  def test_an_unexpected_error_falls_back_without_the_access_token
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      raise ArgumentError, %(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)
    }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, %(ArgumentError: header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF)) }
  end

  def test_images_past_twenty_are_dropped_and_recorded
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @initiates_image_upload.initiate(access_token: "token", person_urn: "urn:li:person:1") }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com/1", image_urn: "urn:li:image:1")
    }
    stubs { @uploads_image.upload_bytes("PNG", content_type: "image/png", upload_url: "https://upload.example.com/1", access_token: "token") }.with { Outcome.success }

    uploaded = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 22), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal 20, uploaded.size
    verify { @records_media_fallback.record(@crosspost, "LinkedIn takes at most 20 images; dropped 2") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: 20 * 1024 * 1024) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end

  # A real file, so the test can see the uploader delete it
  def stub_video_download(content_type, size:)
    path = Tempfile.create(["media", ".mp4"]).tap(&:close).path
    stubs { |m| @downloads_media.download_to_tempfile(m.that { |item| item.url == MP4_URL }, max_bytes: MAX_VIDEO_BYTES) }.with {
      Result.success(DownloadsMedia::DownloadedFile.new(path:, size:, content_type:))
    }
    path
  end

  def stub_video_upload(path, thumbnail:)
    stubs { @uploads_video.upload(path, thumbnail:, access_token: "token", person_urn: "urn:li:person:1") }.with { Result.success(VIDEO_URN) }
  end
end
