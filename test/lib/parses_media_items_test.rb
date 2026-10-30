require "test_helper"

class ParsesMediaItemsTest < ActiveSupport::TestCase
  def setup
    @subject = ParsesMediaItems.new
  end

  def test_reads_every_contract_field
    items = @subject.parse([{
      "type" => "video", "url" => "https://example.com/loop.mp4",
      "poster_url" => "https://example.com/loop.jpg", "alt" => "A map",
      "presentation" => "gif", "mime" => "video/mp4",
      "width" => 800, "height" => 600, "bytes" => 612_345
    }])

    assert_equal [MediaItem.new(
      type: "video", url: "https://example.com/loop.mp4",
      poster_url: "https://example.com/loop.jpg", alt: "A map", presentation: "gif",
      mime: "video/mp4", width: 800, height: 600, bytes: 612_345
    )], items
    assert items.first.video?
  end

  def test_keeps_only_image_and_video_items_with_http_urls
    items = @subject.parse([
      {"type" => "image", "url" => "https://example.com/a.png"},
      {"type" => "audio", "url" => "https://example.com/a.mp3"},
      {"type" => "image", "url" => "ftp://example.com/a.png"},
      {"type" => "image"},
      "https://example.com/bare.png"
    ])

    assert_equal ["https://example.com/a.png"], items.map(&:url)
  end

  def test_drops_numbers_that_are_not_positive_integers
    item = @subject.parse([{
      "type" => "image", "url" => "https://example.com/a.png",
      "width" => "800", "height" => 0, "bytes" => -1
    }]).first

    assert_nil item.width
    assert_nil item.height
    assert_nil item.bytes
  end

  def test_missing_alt_is_an_empty_string
    assert_equal "", @subject.parse([{"type" => "image", "url" => "https://example.com/a.png"}]).first.alt
  end

  def test_nil_parses_to_nothing
    assert_equal [], @subject.parse(nil)
  end
end
