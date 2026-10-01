require "test_helper"

class Platforms::Bsky::UploadsBskyMediaTest < ActiveSupport::TestCase
  JPG_URL = "https://example.com/media/still.jpg"
  PNG_URL = "https://example.com/media/still.png"
  MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @fits_image_within_byte_limit = Mocktail.of_next(FitsImageWithinByteLimit)
    @measures_aspect_ratio = Mocktail.of_next(Platforms::Bsky::MeasuresAspectRatio)
    @uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Bsky::UploadsBskyMedia.new
    @crosspost = crossposts(:admin_bsky_crosspost)
  end

  def test_uploads_each_image_with_its_alt_text_and_aspect_ratio
    stub_image(JPG_URL, "JPG", "image/jpeg", blob: "blob-1", aspect_ratio: {"width" => 4, "height" => 3})
    stub_image(PNG_URL, "PNG", "image/png", blob: "blob-2", aspect_ratio: nil)

    images = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => JPG_URL, "alt" => "An orange square"},
      {"type" => "image", "url" => PNG_URL}
    ]), :record_manager)

    assert_equal [
      {"alt" => "An orange square", "image" => "blob-1", "aspectRatio" => {"width" => 4, "height" => 3}},
      {"alt" => "", "image" => "blob-2"}
    ], images
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    assert_equal [], @subject.upload(@crosspost, config(nil), :record_manager)
    verify_never_called { @downloads_media.download }
  end

  def test_a_video_falls_back_until_bluesky_video_ships
    images = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky video is not supported yet") }
  end

  def test_a_type_bluesky_does_not_take_falls_back
    stub_download(PNG_URL, "<svg/>", "image/svg+xml")

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky takes JPEG, PNG, WebP and GIF, not image/svg+xml (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: MAX_DOWNLOAD_BYTES) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_image_that_cannot_be_brought_within_two_megabytes_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { Result.failure("could not fit image within 2000000 bytes") }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Could not fit #{PNG_URL} within Bluesky's 2000000 bytes: could not fit image within 2000000 bytes") }
  end

  def test_an_upload_bluesky_refuses_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { fitted("PNG", "image/png") }
    stubs { @uploads_bsky_blob.upload("PNG", "image/png", :record_manager) }.with { Result.failure("Bluesky refused the upload (HTTP 400): {}") }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "Bluesky refused the upload (HTTP 400): {}") }
  end

  def test_images_past_four_are_dropped_and_recorded
    stub_image(PNG_URL, "PNG", "image/png", blob: "blob-2", aspect_ratio: nil)

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 5), :record_manager)

    assert_equal 4, images.size
    verify { @records_media_fallback.record(@crosspost, "Bluesky takes at most 4 images; dropped 1") }
  end

  def test_an_unexpected_error_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @fits_image_within_byte_limit.fit("PNG", "image/png", max_bytes: 2_000_000) }.with { raise NoMethodError, "undefined method 'bytes' for nil" }

    images = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]), :record_manager)

    assert_equal [], images
    verify { @records_media_fallback.record(@crosspost, "NoMethodError: undefined method 'bytes' for nil") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def fitted(bytes, content_type)
    Result.success(FitsImageWithinByteLimit::FittedImage.new(bytes:, content_type:))
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: MAX_DOWNLOAD_BYTES) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end

  def stub_image(url, bytes, content_type, blob:, aspect_ratio:)
    stub_download(url, bytes, content_type)
    stubs { @fits_image_within_byte_limit.fit(bytes, content_type, max_bytes: 2_000_000) }.with { fitted(bytes, content_type) }
    stubs { @uploads_bsky_blob.upload(bytes, content_type, :record_manager) }.with { Result.success(blob) }
    stubs { |m| @measures_aspect_ratio.measure(m.that { |item| item.url == url }, bytes) }.with { aspect_ratio }
  end
end
