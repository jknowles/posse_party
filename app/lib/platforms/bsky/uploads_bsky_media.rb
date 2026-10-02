class Platforms::Bsky
  class UploadsBskyMedia
    MAX_IMAGES = 4
    MAX_IMAGE_BYTES = 2_000_000
    # A larger image is scaled down to fit, so the download may be bigger than Bluesky takes
    MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024
    CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @fits_image_within_byte_limit = FitsImageWithinByteLimit.new
      @measures_aspect_ratio = MeasuresAspectRatio.new
      @uploads_bsky_blob = UploadsBskyBlob.new
      @records_media_fallback = RecordsMediaFallback.new
    end

    # Returns the app.bsky.embed.images entries, or [] when the post goes out without media
    def upload(crosspost, crosspost_config, record_manager)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return [] if selection.empty?
      raise MediaUnavailable, "Bluesky video is not supported yet" if selection.video

      images = selection.images.map { |item| upload_image(item, record_manager) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "Bluesky takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
      images
    rescue => e
      # Any error in the media step posts without media, never fails the post
      @records_media_fallback.record(crosspost, e.is_a?(MediaUnavailable) ? e.message : "#{e.class}: #{e.message}")
      []
    end

    private

    def upload_image(item, record_manager)
      download = @downloads_media.download(item, max_bytes: MAX_DOWNLOAD_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless CONTENT_TYPES.include?(content_type)
        raise MediaUnavailable, "Bluesky takes JPEG, PNG, WebP and GIF, not #{content_type} (#{item.url})"
      end

      fitted = @fits_image_within_byte_limit.fit(download.data.bytes, content_type, max_bytes: MAX_IMAGE_BYTES)
      raise MediaUnavailable, "Could not fit #{item.url} within Bluesky's #{MAX_IMAGE_BYTES} bytes: #{fitted.error}" if fitted.failure?

      blob = @uploads_bsky_blob.upload(fitted.data.bytes, fitted.data.content_type, record_manager)
      raise MediaUnavailable, blob.error if blob.failure?

      {"alt" => item.alt, "image" => blob.data, "aspectRatio" => @measures_aspect_ratio.measure(item, fitted.data.bytes)}.compact
    end
  end
end
