require "test_helper"

class Platforms::Mastodon::UploadsMastodonMediaTest < ActiveSupport::TestCase
  GIF_URL = "https://example.com/media/loop.gif"
  PNG_URL = "https://example.com/media/still.png"
  MAX_BYTES = 16 * 1024 * 1024

  def setup
    @downloads_media = Mocktail.of_next(DownloadsMedia)
    @calls_mastodon_media_api = Mocktail.of_next(Platforms::Mastodon::CallsMastodonMediaApi)
    @waits_for_processing = Mocktail.of_next(WaitsForProcessing)
    @records_media_fallback = Mocktail.of_next(RecordsMediaFallback)
    @subject = Platforms::Mastodon::UploadsMastodonMedia.new
    @crosspost = crossposts(:admin_mastodon_crosspost)
    @account = @crosspost.account
  end

  def test_uploads_each_image_mastodon_processes_at_once
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: true)
    stub_upload("PNG", ".png", "", id: "2", ready: true)

    media = @subject.upload(@crosspost, config([
      {"type" => "image", "url" => GIF_URL, "alt" => "A loop"},
      {"type" => "image", "url" => PNG_URL}
    ]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1", "2"], ready?: true), media
    verify_never_called { @waits_for_processing.wait }
    verify_never_called { @records_media_fallback.record }
  end

  def test_no_media_uploads_nothing
    media = @subject.upload(@crosspost, config(nil))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify_never_called { @downloads_media.download }
  end

  def test_waits_for_media_mastodon_is_still_processing
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(true) }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: true), media
  end

  def test_media_still_processing_when_the_wait_runs_out_is_left_to_finish
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { false }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: false), media
    verify_never_called { @records_media_fallback.record }
  end

  def test_media_mastodon_cannot_process_falls_back
    stub_download(GIF_URL, "GIF89a", "image/gif")
    stub_upload("GIF89a", ".gif", "A loop", id: "1", ready: false)
    stubs(ignore_block: true) { @waits_for_processing.wait }.with { |call| call.block.call }
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.failure("Mastodon could not process media 1 (HTTP 422): {}") }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => GIF_URL, "alt" => "A loop"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon could not process media 1 (HTTP 422): {}") }
  end

  def test_a_video_falls_back_until_mastodon_video_ships
    media = @subject.upload(@crosspost, config([{"type" => "video", "url" => "https://example.com/media/loop.mp4"}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon video is not supported yet") }
  end

  def test_a_type_mastodon_does_not_take_falls_back
    stub_download(PNG_URL, "<svg/>", "image/svg+xml")

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon takes JPEG, PNG, GIF and WebP, not image/svg+xml (#{PNG_URL})") }
  end

  def test_a_failed_download_falls_back
    stubs { @downloads_media.download(MediaItem.new(type: "image", url: PNG_URL, alt: ""), max_bytes: MAX_BYTES) }.with {
      Result.failure("Could not download #{PNG_URL}: HTTP 404")
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Could not download #{PNG_URL}: HTTP 404") }
  end

  def test_an_upload_mastodon_refuses_falls_back
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @calls_mastodon_media_api.upload(@account, bytes: "PNG", extension: ".png", description: "") }.with {
      Result.failure("Mastodon refused the upload (HTTP 413): {}")
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon refused the upload (HTTP 413): {}") }
  end

  def test_images_past_four_are_dropped_and_recorded
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("PNG", ".png", "", id: "2", ready: true)

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}] * 6))

    assert_equal ["2", "2", "2", "2"], media.ids
    verify { @records_media_fallback.record(@crosspost, "Mastodon takes at most 4 images; dropped 2") }
  end

  def test_truncates_alt_text_to_mastodons_limit
    stub_download(PNG_URL, "PNG", "image/png")
    stub_upload("PNG", ".png", ("a" * 1600).truncate(1500), id: "2", ready: true)

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL, "alt" => "a" * 1600}]))

    assert_equal ["2"], media.ids
  end

  def test_an_unexpected_error_falls_back_without_the_access_token
    stub_download(PNG_URL, "PNG", "image/png")
    stubs { @calls_mastodon_media_api.upload(@account, bytes: "PNG", extension: ".png", description: "") }.with {
      raise ArgumentError, %(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)
    }

    media = @subject.upload(@crosspost, config([{"type" => "image", "url" => PNG_URL}]))

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, %(ArgumentError: header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF)) }
  end

  def test_finishing_reports_media_that_is_now_ready
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(true) }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: true), media
  end

  def test_finishing_reports_media_still_processing
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.success(false) }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids: ["1"], ready?: false), media
  end

  def test_finishing_falls_back_when_processing_failed
    stubs { @calls_mastodon_media_api.check(@account, "1") }.with { Result.failure("Mastodon could not process media 1 (HTTP 422): {}") }

    media = @subject.finish(@crosspost, ["1"])

    assert_equal Platforms::Mastodon::UploadsMastodonMedia::NONE, media
    verify { @records_media_fallback.record(@crosspost, "Mastodon could not process media 1 (HTTP 422): {}") }
  end

  private

  def config(media)
    CrosspostConfig.new(media:)
  end

  def stub_download(url, bytes, content_type)
    stubs { |m| @downloads_media.download(m.that { |item| item.url == url }, max_bytes: MAX_BYTES) }.with {
      Result.success(DownloadsMedia::Downloaded.new(bytes:, content_type:))
    }
  end

  def stub_upload(bytes, extension, description, id:, ready:)
    stubs { @calls_mastodon_media_api.upload(@account, bytes:, extension:, description:) }.with {
      Result.success(Platforms::Mastodon::CallsMastodonMediaApi::Uploaded.new(id:, ready?: ready))
    }
  end
end
