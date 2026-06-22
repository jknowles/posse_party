class Platforms::Pixelfed
  # Publishes a crosspost to a Pixelfed instance via the Mastodon-compatible API.
  # Pixelfed is photo-first: posts without an image are skipped (mirroring the
  # Instagram path). Each image is uploaded to /api/v1/media and attached to a
  # new status created at /api/v1/statuses.
  class SyndicatesPixelfedPost
    STATUSES_PATH = "/api/v1/statuses".freeze
    # Pixelfed albums currently support up to 10 images.
    MAX_MEDIA = 10

    def initialize
      @uploads_media = UploadsMedia.new
    end

    def syndicate!(crosspost, crosspost_content)
      base_url = crosspost.account.credentials["base_url"]
      access_token = crosspost.account.credentials["access_token"]

      image_urls = image_urls_from(crosspost.post)
      if image_urls.empty?
        crosspost.update!(status: "skipped")
        return PublishesCrosspost::Result.new(success?: true, message: "Skipped: Pixelfed posts require an image")
      end

      media_ids = image_urls.map { |url| @uploads_media.upload(url, base_url:, access_token:) }

      response = HTTParty.post(
        "#{base_url}#{STATUSES_PATH}",
        headers: {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json"
        },
        body: {status: crosspost_content, media_ids: media_ids}.to_json
      )

      if response.success? && (post_id = response.dig("id")).present?
        crosspost.update!(
          remote_id: post_id,
          url: response["url"],
          content: crosspost_content,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      else
        PublishesCrosspost::Result.new(
          success?: false,
          message: "Failed to create Pixelfed post (HTTP #{response.code}). Response: #{response.body}"
        )
      end
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "Failed to syndicate to Pixelfed", error: e)
    end

    private

    # Images only for now; video media is skipped (Pixelfed video upload is
    # asynchronous over the Mastodon API and is a future enhancement).
    def image_urls_from(post)
      post.media
        .reject { |media| media["type"] == "video" }
        .pluck("url")
        .compact_blank
        .first(MAX_MEDIA)
    end
  end
end
