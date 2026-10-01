class Platforms::Bsky
  class MeasuresAspectRatio
    # The feed's width and height win; without both, libvips reads them from the image header.
    # Bluesky treats the aspect ratio as optional, so an unreadable image gets none.
    def measure(item, bytes)
      width, height = (item.width && item.height) ? [item.width, item.height] : read(bytes)
      {"width" => width, "height" => height} if width && height
    end

    private

    def read(bytes)
      require "vips"
      image = Vips::Image.new_from_buffer(bytes, "")
      [image.width, image.height]
    rescue LoadError
      nil
    rescue Vips::Error
      nil
    end
  end
end
