class Platforms::Mastodon
  class UploadsMastodonMedia
    MAX_IMAGES = 4
    MAX_BYTES = 16 * 1024 * 1024
    MAX_VIDEO_BYTES = 99 * 1024 * 1024
    MAX_DESCRIPTION_LENGTH = 1_500
    EXTENSIONS = {"image/jpeg" => ".jpg", "image/png" => ".png", "image/gif" => ".gif", "image/webp" => ".webp"}.freeze
    VIDEO_TYPES = %w[video/mp4 video/quicktime video/webm].freeze

    Media = Struct.new(:ids, :ready?, keyword_init: true)
    NONE = Media.new(ids: [], ready?: true)

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @calls_mastodon_media_api = CallsMastodonMediaApi.new
      @waits_for_processing = WaitsForProcessing.new
      @records_media_fallback = RecordsMediaFallback.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def upload(crosspost, crosspost_config)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return NONE if selection.empty?

      uploaded = selection.video ? [upload_video(crosspost.account, selection.video)] : selection.images.map { |item| upload_image(crosspost.account, item) }
      record_drop(crosspost, selection) if selection.dropped.positive?
      processing = uploaded.reject(&:ready?).map(&:id)
      Media.new(ids: uploaded.map(&:id), ready?: processing.empty? || @waits_for_processing.wait { processed?(crosspost.account, processing) })
    rescue => e
      fall_back(crosspost, e)
    end

    # Checks once on media an earlier attempt left processing
    def finish(crosspost, ids)
      Media.new(ids:, ready?: processed?(crosspost.account, ids))
    rescue => e
      fall_back(crosspost, e)
    end

    private

    def upload_image(account, item)
      download = @downloads_media.download(item, max_bytes: MAX_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless (extension = EXTENSIONS[content_type])
        raise MediaUnavailable, "Mastodon takes JPEG, PNG, GIF and WebP, not #{content_type} (#{item.url})"
      end

      upload = @calls_mastodon_media_api.upload(account, bytes: download.data.bytes, extension:, description: item.alt.truncate(MAX_DESCRIPTION_LENGTH))
      raise MediaUnavailable, upload.error if upload.failure?

      upload.data
    end

    # A video always goes up still processing: Mastodon transcodes it, and makes a silent one a gifv
    def upload_video(account, item)
      download = @downloads_media.download_to_tempfile(item, max_bytes: MAX_VIDEO_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      begin
        content_type = download.data.content_type
        unless VIDEO_TYPES.include?(content_type)
          raise MediaUnavailable, "Mastodon takes MP4, QuickTime and WebM video, not #{content_type} (#{item.url})"
        end

        upload = @calls_mastodon_media_api.upload_file(account, path: download.data.path, content_type:, description: item.alt.truncate(MAX_DESCRIPTION_LENGTH))
        raise MediaUnavailable, upload.error if upload.failure?

        upload.data
      ensure
        File.delete(download.data.path)
      end
    end

    def record_drop(crosspost, selection)
      @records_media_fallback.record(crosspost, if selection.video
        "Mastodon posts a video on its own; dropped #{selection.dropped}"
      else
        "Mastodon takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}"
      end)
    end

    def processed?(account, ids)
      ids.all? { |id|
        check = @calls_mastodon_media_api.check(account, id)
        raise MediaUnavailable, check.error if check.failure?

        check.data
      }
    end

    # Any error in the media step posts the text without media, never fails the post
    def fall_back(crosspost, error)
      reason = error.is_a?(MediaUnavailable) ? error.message : "#{error.class}: #{error.message}"
      @records_media_fallback.record(crosspost, @redacts_bearer_token.redact(reason))
      NONE
    end
  end
end
