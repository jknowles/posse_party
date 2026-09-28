class FitsImageWithinByteLimit
  FittedImage = Struct.new(:bytes, :content_type, keyword_init: true)

  MAX_WIDTH = 1200
  JPEG_QUALITIES = [85, 75, 65, 50].freeze

  # Returns the image untouched when it already fits. Otherwise scales it down to MAX_WIDTH and
  # re-encodes it as JPEG, stepping down quality until it fits, and fails if it never does.
  def fit(image_bytes, content_type, max_bytes:)
    return Result.success(FittedImage.new(bytes: image_bytes, content_type: content_type)) if image_bytes.bytesize <= max_bytes

    require "vips"
    image = downscale(image_bytes)
    jpeg_bytes = JPEG_QUALITIES.lazy
      .map { |quality| image.write_to_buffer(".jpg", Q: quality, strip: true) }
      .find { |bytes| bytes.bytesize <= max_bytes }

    if jpeg_bytes
      Result.success(FittedImage.new(bytes: jpeg_bytes, content_type: "image/jpeg"))
    else
      Result.failure("could not fit image within #{max_bytes} bytes")
    end
  rescue LoadError => e
    Result.failure("could not load libvips: #{e.message}")
  rescue Vips::Error => e
    Result.failure("could not decode image: #{e.message.strip}")
  end

  private

  # thumbnail_buffer shrinks while decoding, so a huge source is never held at full size. It fits the
  # image in a width x height box, so an effectively unbounded height limits only the width. It also
  # reads the source only once, so the small result is copied to memory for the repeated JPEG encodes.
  def downscale(image_bytes)
    image = Vips::Image.thumbnail_buffer(image_bytes, MAX_WIDTH, height: 10_000_000, size: :down)
      .colourspace("srgb")
    (image.has_alpha? ? image.flatten(background: [255, 255, 255]) : image).copy_memory
  end
end
