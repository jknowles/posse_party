class Platforms::Bsky
  class SyndicatesBskyPost
    PDS_URL = "https://bsky.social"

    def initialize
      @composes_post_record = ComposesPostRecord.new
    end

    def syndicate!(crosspost, crosspost_config, crosspost_content, rich_text_facets)
      session = Bskyrb::Session.new(
        Bskyrb::Credentials.new(
          crosspost.account.credentials["email"],
          crosspost.account.credentials["password"]
        ), PDS_URL
      )
      record_manager = Bskyrb::RecordManager.new(session)
      composed = @composes_post_record.compose(crosspost, crosspost_config, text: crosspost_content, facets: rich_text_facets, record_manager:)
      uri = post!(composed.record, record_manager)
      if uri.nil?
        PublishesCrosspost::Result.new(success?: false, message: "Failed to create Bsky post")
      else
        url = uri_to_url(uri, session)
        crosspost.update!(
          remote_id: uri,
          url: url,
          content: composed.text,
          status: "published",
          published_at: Now.time
        )
        PublishesCrosspost::Result.new(success?: true)
      end
    rescue Bskyrb::UnauthorizedError => e
      PublishesCrosspost::Result.new(success?: false, message: "Failed to authenticate to Bsky (invalid credentials)", error: e)
    rescue => e
      PublishesCrosspost::Result.new(success?: false, message: "Failed to syndicate to Bsky", error: e)
    end

    private

    def post!(record, record_manager)
      result = record_manager.create_record(record)
      if result["error"].present?
        raise "Failed to create Bsky post: #{result["error"]} - #{result["message"]}. Record we sent follows: #{record.inspect}"
      end

      result&.dig("uri")
    end

    def uri_to_url(uri, session)
      bsky_handle = DIDKit::Resolver.new.get_verified_handle(session.did)
      post_id = uri[/[^\/]+$/]
      "https://bsky.app/profile/#{bsky_handle}/post/#{post_id}"
    end
  end
end
