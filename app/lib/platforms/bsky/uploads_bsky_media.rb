class Platforms::Bsky
  class UploadsBskyMedia
    MAX_IMAGES = 4
    MAX_IMAGE_BYTES = 2_000_000
    # A larger image is scaled down to fit, so the download may be bigger than Bluesky takes
    MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024
    # Bluesky takes up to 300 MB; this instance stops at 100 MB to stay inside the job's time limit
    MAX_VIDEO_BYTES = 100 * 1024 * 1024
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

    # Returns the post's media embed, or nil when the post goes out without media
    def upload(crosspost, crosspost_config, record_manager)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return if selection.empty?

      embed = if selection.video
        video_embed(selection.video, record_manager)
      else
        {"$type" => "app.bsky.embed.images", "images" => selection.images.map { |item| upload_image(item, record_manager) }}
      end
      record_drop(crosspost, selection) if selection.dropped.positive?
      embed
    rescue => e
      # Any error in the media step posts without media, never fails the post
      @records_media_fallback.record(crosspost, e.is_a?(MediaUnavailable) ? e.message : "#{e.class}: #{e.message}")
      nil
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

    # The simple route: the video goes to the account's PDS as a blob, and Bluesky processes it once
    # the post appears, so the post shows the video as missing for a few seconds
    def video_embed(item, record_manager)
      download = @downloads_media.download_to_tempfile(item, max_bytes: MAX_VIDEO_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      begin
        unless download.data.content_type == "video/mp4"
          raise MediaUnavailable, "Bluesky takes MP4 video, not #{download.data.content_type} (#{item.url})"
        end

        blob = @uploads_bsky_blob.upload_file(download.data.path, "video/mp4", record_manager)
        raise MediaUnavailable, blob.error if blob.failure?

        {
          "$type" => "app.bsky.embed.video",
          "video" => blob.data,
          "alt" => item.alt.presence,
          "aspectRatio" => ({"width" => item.width, "height" => item.height} if item.width && item.height),
          "presentation" => ("gif" if item.presentation == "gif")
        }.compact
      ensure
        File.delete(download.data.path)
      end
    end

    def record_drop(crosspost, selection)
      @records_media_fallback.record(crosspost, if selection.video
        "Bluesky posts a video on its own; dropped #{selection.dropped}"
      else
        "Bluesky takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}"
      end)
    end
  end
end
