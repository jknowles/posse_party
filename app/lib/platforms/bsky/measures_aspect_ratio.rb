class Platforms::Bsky
  class MeasuresAspectRatio
    # EXIF orientations 5 to 8 display the stored pixels turned a quarter turn
    QUARTER_TURNS = 5..8

    # Measures the image Bluesky is sent, turned the way its orientation tag says it displays: a
    # feed's width and height describe the stored pixels, which a re-encode or a viewer may rotate.
    # The feed's numbers count only when libvips cannot read the image, and Bluesky treats the
    # aspect ratio as optional, so an image neither describes gets none.
    def measure(item, bytes)
      width, height = read(bytes) || [item.width, item.height]
      {"width" => width, "height" => height} if width && height
    end

    private

    def read(bytes)
      require "vips"
      image = Vips::Image.new_from_buffer(bytes, "")
      QUARTER_TURNS.cover?(orientation(image)) ? [image.height, image.width] : [image.width, image.height]
    rescue LoadError
      nil
    rescue Vips::Error
      nil
    end

    def orientation(image)
      image.get_typeof("orientation").zero? ? 1 : image.get("orientation")
    end
  end
end
