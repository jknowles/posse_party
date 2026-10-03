class Platforms::Linkedin
  class UploadsMedia
    MAX_IMAGES = 20
    MAX_IMAGE_BYTES = 20 * 1024 * 1024
    # LinkedIn takes 75 KB to 500 MB; this instance stops at 100 MB to stay inside the job's time limit
    MIN_VIDEO_BYTES = 75 * 1024
    MAX_VIDEO_BYTES = 100 * 1024 * 1024
    THUMBNAIL_TYPES = %w[image/jpeg image/png].freeze
    CONTENT_TYPES = %w[image/jpeg image/png image/gif].freeze

    # A video LinkedIn is still processing when the wait runs out is posted later, by finish
    Uploaded = Struct.new(:urn, :alt, :processing, keyword_init: true)

    def initialize
      @parses_media_items = ParsesMediaItems.new
      @selects_media = SelectsMedia.new
      @downloads_media = DownloadsMedia.new
      @initiates_image_upload = InitiatesImageUpload.new
      @uploads_image = UploadsImage.new
      @uploads_video = UploadsVideo.new
      @waits_for_processing = WaitsForProcessing.new
      @records_media_fallback = RecordsMediaFallback.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def upload(crosspost, crosspost_config, access_token:, person_urn:)
      selection = @selects_media.select(@parses_media_items.parse(crosspost_config.media), max_images: MAX_IMAGES)
      return [] if selection.empty?

      uploaded = if selection.video
        [upload_video(selection.video, access_token:, person_urn:)]
      else
        selection.images.map { |item| upload_image(item, access_token:, person_urn:) }
      end
      record_drop(crosspost, selection) if selection.dropped.positive?
      uploaded
    rescue => e
      fall_back(crosspost, e)
    end

    # Checks once on a video an earlier attempt left processing
    def finish(crosspost, urn, access_token:)
      [Uploaded.new(urn:, processing: !available?(urn, access_token:))]
    rescue => e
      fall_back(crosspost, e)
    end

    private

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

    # LinkedIn processes a video before it can be posted, so this waits for it a while
    def upload_video(item, access_token:, person_urn:)
      urn = upload_video_file(item, access_token:, person_urn:)
      Uploaded.new(urn:, processing: !@waits_for_processing.wait { available?(urn, access_token:) })
    end

    def upload_video_file(item, access_token:, person_urn:)
      download = @downloads_media.download_to_tempfile(item, max_bytes: MAX_VIDEO_BYTES)
      raise MediaUnavailable, download.error if download.failure?

      begin
        video = download.data
        raise MediaUnavailable, "LinkedIn takes MP4 video, not #{video.content_type} (#{item.url})" unless video.content_type == "video/mp4"
        raise MediaUnavailable, "LinkedIn takes video of at least #{MIN_VIDEO_BYTES} bytes, and #{item.url} is #{video.size}" if video.size < MIN_VIDEO_BYTES

        upload = @uploads_video.upload(video.path, thumbnail: thumbnail(item), access_token:, person_urn:)
        raise MediaUnavailable, upload.error if upload.failure?

        upload.data
      ensure
        File.delete(download.data.path)
      end
    end

    # A poster that cannot be downloaded, or that is not a JPEG or PNG, leaves LinkedIn to choose a frame
    def thumbnail(item)
      return if item.poster_url.blank?

      poster = @downloads_media.download(MediaItem.new(type: "image", url: item.poster_url), max_bytes: MAX_IMAGE_BYTES)
      poster.data.bytes if poster.success? && THUMBNAIL_TYPES.include?(poster.data.content_type)
    end

    def available?(urn, access_token:)
      status = @uploads_video.status(urn, access_token:)
      raise MediaUnavailable, status.error if status.failure?
      raise MediaUnavailable, "LinkedIn could not process video #{urn}" if status.data == "PROCESSING_FAILED"

      status.data == "AVAILABLE"
    end

    def record_drop(crosspost, selection)
      @records_media_fallback.record(crosspost, if selection.video
        "LinkedIn posts a video on its own; dropped #{selection.dropped}"
      else
        "LinkedIn takes at most #{MAX_IMAGES} images; dropped #{selection.dropped}"
      end)
    end

    # Any error in the media step posts without media, never fails the post
    def fall_back(crosspost, error)
      reason = error.is_a?(MediaUnavailable) ? error.message : "#{error.class}: #{error.message}"
      @records_media_fallback.record(crosspost, @redacts_bearer_token.redact(reason))
      []
    end
  end
end
