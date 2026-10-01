class Platforms::Mastodon
  class UploadsMastodonMedia
    MAX_IMAGES = 4
    MAX_BYTES = 16 * 1024 * 1024
    MAX_DESCRIPTION_LENGTH = 1_500
    EXTENSIONS = {"image/jpeg" => ".jpg", "image/png" => ".png", "image/gif" => ".gif", "image/webp" => ".webp"}.freeze

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
      raise MediaUnavailable, "Mastodon video is not supported yet" if selection.video

      uploaded = selection.images.map { |item| upload_image(crosspost.account, item) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "Mastodon takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
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
