require "test_helper"

class SelectsMediaTest < ActiveSupport::TestCase
  def setup
    @subject = SelectsMedia.new
  end

  def test_takes_images_up_to_the_limit_and_counts_the_rest
    first = MediaItem.new(type: "image", url: "https://example.com/1.png")
    second = MediaItem.new(type: "image", url: "https://example.com/2.png")
    third = MediaItem.new(type: "image", url: "https://example.com/3.png")

    selection = @subject.select([first, second, third], max_images: 2)

    assert_equal [first, second], selection.images
    assert_nil selection.video
    assert_equal 1, selection.dropped
  end

  def test_a_video_wins_over_images
    image = MediaItem.new(type: "image", url: "https://example.com/a.png")
    video = MediaItem.new(type: "video", url: "https://example.com/a.mp4")

    selection = @subject.select([image, video], max_images: 4)

    assert_equal [], selection.images
    assert_equal video, selection.video
    assert_equal 1, selection.dropped
  end

  def test_nothing_selects_nothing
    selection = @subject.select([], max_images: 4)

    assert selection.empty?
  end
end
