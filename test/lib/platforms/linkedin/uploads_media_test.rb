require "test_helper"

class Platforms::Linkedin::UploadsMediaTest < ActiveSupport::TestCase
  GIF_URL = "https://example.com/media/loop.gif"
  PNG_URL = "https://example.com/media/still.png"

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @initiates_image_upload = Mocktail.of_next(Platforms::Linkedin::InitiatesImageUpload)
    @uploads_image = Mocktail.of_next(Platforms::Linkedin::UploadsImage)
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

  def test_a_video_falls_back_until_linkedin_video_ships
    uploaded = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]), access_token: "token", person_urn: "urn:li:person:1")

    assert_equal [], uploaded
    verify { @records_media_fallback.record(@crosspost, "LinkedIn video is not supported yet") }
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
end
