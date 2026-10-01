require "test_helper"
require "vips"

class Platforms::Bsky::MeasuresAspectRatioTest < ActiveSupport::TestCase
  def setup
    @subject = Platforms::Bsky::MeasuresAspectRatio.new
    @png = Vips::Image.black(300, 200, bands: 3).write_to_buffer(".png")
  end

  def test_takes_the_width_and_height_the_feed_sends
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600, height: 900)

    assert_equal({"width" => 1600, "height" => 900}, @subject.measure(item, @png))
  end

  def test_reads_the_size_from_the_image_when_the_feed_sends_none
    item = MediaItem.new(type: "image", url: "https://example.com/a.png")

    assert_equal({"width" => 300, "height" => 200}, @subject.measure(item, @png))
  end

  def test_reads_the_size_from_the_image_when_the_feed_sends_only_a_width
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600)

    assert_equal({"width" => 300, "height" => 200}, @subject.measure(item, @png))
  end

  def test_measures_nothing_in_bytes_that_are_not_an_image
    item = MediaItem.new(type: "image", url: "https://example.com/a.png")

    assert_nil @subject.measure(item, "<html>not an image</html>")
  end
end
