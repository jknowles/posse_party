class Platforms::Linkedin
  class SyndicatesLinkedinPost
    KEPT_VIDEO = "linkedin_video"

    def initialize
      @limits_to_one_url = LimitsToOneUrl.new
      @scrapes_og_image = ScrapesOgImage.new
      @initiates_image_upload = InitiatesImageUpload.new
      @uploads_image = UploadsImage.new
      @uploads_media = UploadsMedia.new
      @publishes_post = PublishesPost.new
    end

    def syndicate!(crosspost:, crosspost_config:, crosspost_content:, author_credential:)
      return PublishesCrosspost::Result.new(success?: false, message: "Missing access token") if (access_token = crosspost.account.credentials["access_token"]).blank?
      return PublishesCrosspost::Result.new(success?: false, message: "Missing #{author_credential} credential") if (author_urn = crosspost.account.credentials[author_credential]).blank?

      # With media there is no card: the post's one URL stays in the commentary
      media = @uploads_media.upload(crosspost, crosspost_config, access_token:, author_urn:)
      content, url = if media.any?
        @limits_to_one_url.limit_with_media(crosspost_config, crosspost_content).to_a
      else
        @limits_to_one_url.limit(crosspost_config, crosspost_content).to_a
      end
      return finish_later(crosspost, content, media.first.urn) if media.any?(&:processing)

      image_urn = card_thumbnail(url, crosspost_config, access_token:, author_urn:) if url.present?
      publish!(crosspost, content, crosspost_config, access_token:, author_urn:, image_urn:, url:, media:)
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "An unexpected error occurred while crossposting to LinkedIn", error: e)
    end

    # Posts a video an earlier attempt left processing, once LinkedIn has it ready. A video LinkedIn
    # cannot process posts the commentary alone, which already carries the post's link.
    def finish!(crosspost, author_credential:)
      kept = crosspost.metadata[KEPT_VIDEO]
      return PublishesCrosspost::Result.new(success?: false, message: "No LinkedIn video is waiting to be posted") if kept.blank?

      access_token = crosspost.account.credentials["access_token"]
      media = @uploads_media.finish(crosspost, kept["urn"], access_token:)
      return PublishesCrosspost::Result.new(success?: true, needs_to_finish?: true) if media.any?(&:processing)

      publish!(crosspost, kept["content"], CrosspostConfig.new, access_token:, author_urn: crosspost.account.credentials[author_credential], image_urn: nil, url: nil, media:)
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "An unexpected error occurred while crossposting to LinkedIn", error: e)
    end

    private

    # FinishCrosspostJob checks again and posts once LinkedIn has processed the video
    def finish_later(crosspost, content, urn)
      crosspost.update!(metadata: crosspost.metadata.merge(KEPT_VIDEO => {"urn" => urn, "content" => content}))
      PublishesCrosspost::Result.new(success?: true, needs_to_finish?: true)
    end

    def publish!(crosspost, content, crosspost_config, access_token:, author_urn:, image_urn:, url:, media:)
      # Escape special characters that LinkedIn API has issues with
      # Based on known LinkedIn API bug where parentheses cause content truncation
      escaped_content = content.gsub(/([\\|{}@\[\]()<>#*_~])/) { "\\#{$1}" }

      if (publish_result = @publishes_post.publish(escaped_content, crosspost_config, access_token:, author_urn:, image_urn:, url:, media:)).success?
        crosspost.update!(
          remote_id: publish_result.post_urn,
          url: publish_result.url,
          content: content,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      else
        PublishesCrosspost::Result.new(success?: false, message: "Failed to publish LinkedIn post. Error: #{publish_result.message}")
      end
    end

    def card_thumbnail(url, crosspost_config, access_token:, author_urn:)
      og_image = (url == crosspost_config.url) ? crosspost_config.og_image : @scrapes_og_image.scrape(url)
      if og_image.present? &&
          (upload_init_result = @initiates_image_upload.initiate(access_token:, author_urn:)).success? &&
          @uploads_image.upload(og_image, upload_init_result.upload_url, access_token:).success?
        upload_init_result.image_urn
      end
    end
  end
end
