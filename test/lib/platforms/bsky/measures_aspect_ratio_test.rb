require "test_helper"
require "vips"

class Platforms::Bsky::MeasuresAspectRatioTest < ActiveSupport::TestCase
  def setup
    @subject = Platforms::Bsky::MeasuresAspectRatio.new
    @png = Vips::Image.black(300, 200, bands: 3).write_to_buffer(".png")
  end

  def test_measures_the_image_it_is_given_rather_than_the_feeds_numbers
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600, height: 900)

    assert_equal({"width" => 300, "height" => 200}, @subject.measure(item, @png))
  end

  def test_turns_a_photo_the_way_its_orientation_tag_says_it_displays
    sideways = Vips::Image.black(300, 200, bands: 3).copy
    sideways.set_type(GObject::GINT_TYPE, "orientation", 6)
    item = MediaItem.new(type: "image", url: "https://example.com/a.jpg", width: 300, height: 200)

    assert_equal({"width" => 200, "height" => 300}, @subject.measure(item, sideways.jpegsave_buffer))
  end

  def test_falls_back_to_the_feeds_numbers_when_the_image_cannot_be_read
    item = MediaItem.new(type: "image", url: "https://example.com/a.png", width: 1600, height: 900)

    assert_equal({"width" => 1600, "height" => 900}, @subject.measure(item, "<html>not an image</html>"))
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
