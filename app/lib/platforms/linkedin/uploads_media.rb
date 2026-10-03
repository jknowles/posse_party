class Platforms::Linkedin
  class UploadsMedia
    MAX_IMAGES = 20
    MAX_IMAGE_BYTES = 20 * 1024 * 1024
    CONTENT_TYPES = %w[image/jpeg image/png image/gif].freeze

    Uploaded = Struct.new(:urn, :alt, keyword_init: true)

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @initiates_image_upload = InitiatesImageUpload.new
      @uploads_image = UploadsImage.new
      @records_media_fallback = RecordsMediaFallback.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def upload(crosspost, crosspost_config, access_token:, person_urn:)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return [] if selection.empty?
      raise MediaUnavailable, "LinkedIn video is not supported yet" if selection.video

      uploaded = selection.images.map { |item| upload_image(item, access_token:, person_urn:) }
      if selection.dropped.positive?
        @records_media_fallback.record(crosspost, "LinkedIn takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}")
      end
      uploaded
    rescue => e
      fall_back(crosspost, e)
    end

    private

    # Any error in the media step posts without media, never fails the post
    def fall_back(crosspost, error)
      reason = error.is_a?(MediaUnavailable) ? error.message : "#{error.class}: #{error.message}"
      @records_media_fallback.record(crosspost, @redacts_bearer_token.redact(reason))
      []
    end

    def upload_image(item, access_token:, person_urn:)
      download = @downloads_media.download(item, max_bytes: MAX_IMAGE_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      content_type = download.data.content_type
      unless CONTENT_TYPES.include?(content_type)
        raise MediaUnavailable, "LinkedIn takes JPEG, PNG and GIF, not #{content_type} (#{item.url})"
      end

      upload_init = @initiates_image_upload.initiate(access_token:, person_urn:)
      raise MediaUnavailable, upload_init.message unless upload_init.success?

      upload = @uploads_image.upload_bytes(download.data.bytes, content_type:, upload_url: upload_init.upload_url, access_token:)
      raise MediaUnavailable, upload.message unless upload.success?

      Uploaded.new(urn: upload_init.image_urn, alt: item.alt)
    end
  end
end
