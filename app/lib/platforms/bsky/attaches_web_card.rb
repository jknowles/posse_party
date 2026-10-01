class Platforms::Bsky::AttachesWebCard
  # Bluesky rejects the whole post record when a blob is over this size
  THUMB_MAX_BYTES = 1_000_000
  # A larger og:image is scaled down to fit, so the download may be bigger than the thumb
  MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024

  def initialize
    @downloads_media = DownloadsMedia.new
    @fits_image_within_byte_limit = FitsImageWithinByteLimit.new
    @uploads_bsky_blob = Platforms::Bsky::UploadsBskyBlob.new
  end

  def attach!(crosspost_config, record_manager)
    {
      "$type" => "app.bsky.embed.external",
      "external" => {
        "uri" => crosspost_config.url,
        "title" => crosspost_config.og_title.presence || crosspost_config.title,
        "description" => crosspost_config.og_description.presence || crosspost_config.summary.presence || crosspost_config.title.presence || "",
        "thumb" => upload_thumbnail!(crosspost_config.og_image, record_manager)
      }.compact
    }
  end

  private

  def upload_thumbnail!(image_url, record_manager)
    return if image_url.blank?

    download = @downloads_media.download(MediaItem.new(type: "image", url: image_url), max_bytes: MAX_DOWNLOAD_BYTES)
    raise "Failed to download og_image: #{image_url}. #{download.error}" if download.failure?

    fit_result = @fits_image_within_byte_limit.fit(download.data.bytes, download.data.content_type, max_bytes: THUMB_MAX_BYTES)
    if fit_result.failure?
      Rails.logger.warn("Posting Bsky web card without a thumbnail for og_image #{image_url}: #{fit_result.error}")
      return
    end

    upload = @uploads_bsky_blob.upload(fit_result.data.bytes, fit_result.data.content_type, record_manager)
    raise "Failed to upload og_image: #{image_url} to Bsky. #{upload.error}" if upload.failure?

    upload.data
  end
end
