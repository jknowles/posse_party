class Platforms::Linkedin
  class SyndicatesLinkedinPost
    def initialize
      @limits_to_one_url = LimitsToOneUrl.new
      @scrapes_og_image = ScrapesOgImage.new
      @initiates_image_upload = InitiatesImageUpload.new
      @uploads_image = UploadsImage.new
      @uploads_media = UploadsMedia.new
      @publishes_post = PublishesPost.new
    end

    def syndicate!(crosspost, crosspost_config, crosspost_content)
      return PublishesCrosspost::Result.new(success?: false, message: "Missing access token") if (access_token = crosspost.account.credentials["access_token"]).blank?
      return PublishesCrosspost::Result.new(success?: false, message: "Missing person URN") if (person_urn = crosspost.account.credentials["person_urn"]).blank?

      # With media there is no card: the composed text, appended URL included, is the commentary
      media = @uploads_media.upload(crosspost, crosspost_config, access_token:, person_urn:)
      content, url = media.any? ? [crosspost_content, nil] : @limits_to_one_url.limit(crosspost_config, crosspost_content).to_a
      image_urn = card_thumbnail(url, crosspost_config, access_token:, person_urn:) if url.present?

      # Escape special characters that LinkedIn API has issues with
      # Based on known LinkedIn API bug where parentheses cause content truncation
      escaped_content = content.gsub(/([\\|{}@\[\]()<>#*_~])/) { "\\#{$1}" }

      if (publish_result = @publishes_post.publish(escaped_content, crosspost_config, access_token:, person_urn:, image_urn:, url:, media:)).success?
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
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "An unexpected error occurred while crossposting to LinkedIn", error: e)
    end

    private

    def card_thumbnail(url, crosspost_config, access_token:, person_urn:)
      og_image = (url == crosspost_config.url) ? crosspost_config.og_image : @scrapes_og_image.scrape(url)
      if og_image.present? &&
          (upload_init_result = @initiates_image_upload.initiate(access_token:, person_urn:)).success? &&
          @uploads_image.upload(og_image, upload_init_result.upload_url, access_token:).success?
        upload_init_result.image_urn
      end
    end
  end
end
