class Platforms::Bsky
  class ComposesPostRecord
    Composed = Struct.new(:text, :record, keyword_init: true)

    def initialize
      @uploads_bsky_media = UploadsBskyMedia.new
      @keeps_link_with_media = KeepsLinkWithMedia.new
      @attaches_web_card = AttachesWebCard.new
    end

    def compose(crosspost, crosspost_config, text:, facets:, record_manager:)
      images = @uploads_bsky_media.upload(crosspost, crosspost_config, record_manager)
      post = images.any? ? @keeps_link_with_media.keep(crosspost_config, text, facets) : KeepsLinkWithMedia::Post.new(text:, facets:)
      embed = if images.any?
        {"$type" => "app.bsky.embed.images", "images" => images}
      elsif crosspost_config.attach_link
        @attaches_web_card.attach!(crosspost_config, record_manager)
      end

      Composed.new(text: post.text, record: {
        "collection" => "app.bsky.feed.post",
        "$type" => "app.bsky.feed.post",
        "repo" => record_manager.session.did,
        "record" => {
          "$type" => "app.bsky.feed.post",
          "createdAt" => Now.time.iso8601(3),
          "text" => post.text,
          "facets" => post.facets,
          "embed" => embed
        }.compact
      }.compact)
    end
  end
end
