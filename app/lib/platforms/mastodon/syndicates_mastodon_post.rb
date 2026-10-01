class Platforms::Mastodon
  class SyndicatesMastodonPost
    def initialize
      @uploads_mastodon_media = UploadsMastodonMedia.new
      @redacts_bearer_token = RedactsBearerToken.new
    end

    def syndicate!(crosspost, crosspost_config, crosspost_content)
      post_or_finish_later!(crosspost, crosspost_content, @uploads_mastodon_media.upload(crosspost, crosspost_config))
    rescue => e
      failure(e)
    end

    def finish!(crosspost)
      kept = crosspost.metadata["mastodon_media"]
      return PublishesCrosspost::Result.new(success?: false, message: "No Mastodon media is waiting to be posted") if kept.blank?

      post_or_finish_later!(crosspost, kept["status"], @uploads_mastodon_media.finish(crosspost, kept["ids"]))
    rescue => e
      failure(e)
    end

    private

    def post_or_finish_later!(crosspost, status, media)
      if media.ready?
        post!(crosspost, status, media.ids)
      else
        # FinishCrosspostJob checks again and posts once Mastodon has processed the media
        crosspost.update!(metadata: crosspost.metadata.merge("mastodon_media" => {"ids" => media.ids, "status" => status}))
        PublishesCrosspost::Result.new(success?: true, needs_to_finish?: true)
      end
    end

    def post!(crosspost, status, media_ids)
      response = HTTParty.post(
        "#{crosspost.account.credentials["base_url"]}/api/v1/statuses",
        headers: {
          "Authorization" => "Bearer #{crosspost.account.credentials["access_token"]}",
          "Content-Type" => "application/json",
          # Mastodon returns the status it already made for a key it has seen in the last hour
          "Idempotency-Key" => "posse-party-crosspost-#{crosspost.id}"
        },
        body: {status:, media_ids: media_ids.presence}.compact.to_json
      )

      if response.success? && (post_id = response.dig("id")).present?
        crosspost.update!(
          remote_id: post_id,
          url: response["url"],
          content: status,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      else
        PublishesCrosspost::Result.new(
          success?: false,
          message: "Failed to create Mastodon post (HTTP #{response.code}). Response: #{response.body}"
        )
      end
    end

    def failure(error)
      PublishesCrosspost::Result.new(success?: false, message: "Failed to syndicate to Mastodon", error: error.exception(@redacts_bearer_token.redact(error.message)))
    end
  end
end
