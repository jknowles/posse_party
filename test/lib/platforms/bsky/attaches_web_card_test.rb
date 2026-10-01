require "test_helper"
require "vips"

class Platforms::Bsky::AttachesWebCardTest < ActiveSupport::TestCase
  def test_uses_summary_when_og_description_is_missing
    subject = Platforms::Bsky::AttachesWebCard.new
    crosspost_config = CrosspostConfig.new(
      url: "https://example.com/posts/123",
      title: "A Consistent Title",
      summary: "A consistent description",
      og_title: nil,
      og_description: nil,
      og_image: nil
    )

    result = subject.attach!(crosspost_config, nil)

    assert_equal "app.bsky.embed.external", result["$type"]
    assert_equal "https://example.com/posts/123", result["external"]["uri"]
    assert_equal "A Consistent Title", result["external"]["title"]
    assert_equal "A consistent description", result["external"]["description"]
  end

  def test_uses_title_when_summary_and_og_description_are_missing
    subject = Platforms::Bsky::AttachesWebCard.new
    crosspost_config = CrosspostConfig.new(
      url: "https://example.com/posts/123",
      title: "A Consistent Title",
      summary: nil,
      og_title: nil,
      og_description: nil,
      og_image: nil
    )

    result = subject.attach!(crosspost_config, nil)

    assert_equal "app.bsky.embed.external", result["$type"]
    assert_equal "https://example.com/posts/123", result["external"]["uri"]
    assert_equal "A Consistent Title", result["external"]["title"]
    assert_equal "A Consistent Title", result["external"]["description"]
  end

  def test_uploads_an_og_image_behind_a_redirect_as_the_thumb
    uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    subject = Platforms::Bsky::AttachesWebCard.new
    png = Vips::Image.black(10, 10, bands: 3).write_to_buffer(".png")
    blob = {"$type" => "blob", "ref" => {"$link" => "bafkreiexample"}, "mimeType" => "image/png", "size" => png.bytesize}
    stub_request(:get, "https://example.com/og.png").to_return(status: 301, headers: {"Location" => "https://cdn.example.com/og.png"})
    stub_request(:get, "https://cdn.example.com/og.png").to_return(status: 200, body: png, headers: {"Content-Type" => "image/png"})
    stubs { uploads_bsky_blob.upload(png, "image/png", :record_manager) }.with { Result.success(blob) }

    result = subject.attach!(CrosspostConfig.new(url: "https://example.com/posts/123", title: "A title", og_image: "https://example.com/og.png"), :record_manager)

    assert_equal blob, result["external"]["thumb"]
  end

  def test_a_thumb_bluesky_refuses_fails_the_post_as_before
    uploads_bsky_blob = Mocktail.of_next(Platforms::Bsky::UploadsBskyBlob)
    subject = Platforms::Bsky::AttachesWebCard.new
    png = Vips::Image.black(10, 10, bands: 3).write_to_buffer(".png")
    stub_request(:get, "https://example.com/og.png").to_return(status: 200, body: png, headers: {"Content-Type" => "image/png"})
    stubs { uploads_bsky_blob.upload(png, "image/png", :record_manager) }.with { Result.failure("Bluesky refused the upload (HTTP 400): {}") }

    error = assert_raises(RuntimeError) {
      subject.attach!(CrosspostConfig.new(url: "https://example.com/posts/123", title: "A title", og_image: "https://example.com/og.png"), :record_manager)
    }

    assert_equal "Failed to upload og_image: https://example.com/og.png to Bsky. Bluesky refused the upload (HTTP 400): {}", error.message
  end
end
