class Platforms::Bsky::AttachesWebCard
  # Bluesky rejects the whole post record when a blob is over this size
  THUMB_MAX_BYTES = 1_000_000

  def initialize
    @fits_image_within_byte_limit = FitsImageWithinByteLimit.new
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

    image_data, content_type = download_image(image_url)
    raise "Failed to download og_image: #{image_url}" unless image_data

    fit_result = @fits_image_within_byte_limit.fit(image_data, content_type, max_bytes: THUMB_MAX_BYTES)
    if fit_result.failure?
      Rails.logger.warn("Posting Bsky web card without a thumbnail for og_image #{image_url}: #{fit_result.error}")
      return
    end

    # Dropping down to do this ourselves b/c the bsky gem assumes you're reading the image from a file
    # https://github.com/ShreyanJain9/bskyrb/blob/main/lib/bskyrb/records.rb#L36
    upload_response = HTTParty.post(
      record_manager.upload_blob_uri(record_manager.session.pds),
      body: fit_result.data.bytes,
      headers: record_manager.default_authenticated_headers(record_manager.session).merge("Content-Type" => fit_result.data.content_type)
    )
    raise "Failed to upload og_image: #{image_url} to Bsky. Response: #{upload_response}" unless upload_response.success?

    upload_response["blob"]
  end

  def download_image(image_url)
    uri = URI.parse(image_url)
    response = Net::HTTP.get_response(uri)
    return unless response.is_a?(Net::HTTPSuccess)

    content_type = response.content_type || Marcel::MimeType.for(Pathname.new(uri.path))
    [response.body, content_type]
  end
end
