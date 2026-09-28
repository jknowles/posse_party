class FitsImageWithinByteLimit
  FittedImage = Struct.new(:bytes, :content_type, keyword_init: true)

  MAX_WIDTH = 1200
  JPEG_QUALITIES = [85, 75, 65, 50].freeze

  # Returns the image untouched when it already fits. Otherwise scales it down to MAX_WIDTH and
  # re-encodes it as JPEG, stepping down quality until it fits, and fails if it never does.
  def fit(image_bytes, content_type, max_bytes:)
    return Result.success(FittedImage.new(bytes: image_bytes, content_type: content_type)) if image_bytes.bytesize <= max_bytes

    require "vips"
    image = downscale(Vips::Image.new_from_buffer(image_bytes, ""))
    jpeg_bytes = JPEG_QUALITIES.lazy
      .map { |quality| image.write_to_buffer(".jpg", Q: quality, strip: true) }
      .find { |bytes| bytes.bytesize <= max_bytes }

    if jpeg_bytes
      Result.success(FittedImage.new(bytes: jpeg_bytes, content_type: "image/jpeg"))
    else
      Result.failure("could not fit image within #{max_bytes} bytes")
    end
  rescue Vips::Error => e
    Result.failure("could not decode image: #{e.message.strip}")
  end

  private

  def downscale(image)
    srgb_image = image.autorot.colourspace("srgb")
    opaque_image = srgb_image.has_alpha? ? srgb_image.flatten(background: [255, 255, 255]) : srgb_image
    opaque_image.resize([MAX_WIDTH.fdiv(opaque_image.width), 1].min)
  end
end
