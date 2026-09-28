require "test_helper"
require "vips"

class FitsImageWithinByteLimitTest < ActiveSupport::TestCase
  def setup
    @subject = FitsImageWithinByteLimit.new
    # Noise compresses poorly, so this PNG is several megabytes; the alpha band
    # makes it one JPEG cannot carry as-is.
    @oversized_png = Vips::Image.gaussnoise(1600, 2400, mean: 128, sigma: 60)
      .cast(:uchar)
      .bandjoin(255)
      .write_to_buffer(".png")
  end

  def test_returns_an_image_already_within_the_limit_unchanged
    small_png = Vips::Image.black(100, 100, bands: 3).write_to_buffer(".png")

    result = @subject.fit(small_png, "image/png", max_bytes: 1_000_000)

    assert result.success?
    assert_equal small_png, result.data.bytes
    assert_equal "image/png", result.data.content_type
  end

  def test_downscales_and_reencodes_an_oversized_image_as_jpeg_within_the_limit
    assert_operator @oversized_png.bytesize, :>, 1_000_000

    result = @subject.fit(@oversized_png, "image/png", max_bytes: 1_000_000)
    output_image = Vips::Image.new_from_buffer(result.data.bytes, "")

    assert result.success?
    assert_equal "image/jpeg", result.data.content_type
    assert_operator result.data.bytes.bytesize, :<=, 1_000_000
    assert_equal 1200, output_image.width
    assert_equal 1800, output_image.height
    assert_equal false, output_image.has_alpha?
  end

  def test_fails_when_the_image_cannot_be_brought_within_the_limit
    result = @subject.fit(@oversized_png, "image/png", max_bytes: 500)

    assert result.failure?
    assert_match "could not fit image within 500 bytes", result.error
  end

  def test_fails_when_the_bytes_are_not_an_image
    result = @subject.fit("<html>not an image</html>" * 100, "text/html", max_bytes: 1_000)

    assert result.failure?
    assert_match "could not decode image", result.error
  end
end
