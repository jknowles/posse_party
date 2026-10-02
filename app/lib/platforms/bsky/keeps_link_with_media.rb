class Platforms::Bsky
  class KeepsLinkWithMedia
    Post = Struct.new(:text, :facets, keyword_init: true)

    def initialize
      @composes_crosspost_content = PublishesCrosspost::ComposesCrosspostContent.new
      @assembles_rich_text_facets = AssemblesRichTextFacets.new
    end

    # Images take the place of the link card, so the card's link is appended to the text instead,
    # as PublishesCrosspost::RecoversFromInvalidLinkAttachment does when a card is refused
    def keep(crosspost_config, text, facets)
      if crosspost_config.attach_link && crosspost_config.url.present? && !links_to?(facets, crosspost_config.url)
        content = @composes_crosspost_content.compose(CrosspostConfig.new(**crosspost_config.to_h.merge(append_url: true, attach_link: false)), POST_CONSTRAINTS)
        Post.new(text: content.string, facets: @assembles_rich_text_facets.assemble(content.string, content.pattern_ranges))
      else
        Post.new(text:, facets:)
      end
    rescue PublishesCrosspost::UnretriableError => e
      # The feed turned truncation off and the text has no room for the link, so the images go without it
      Rails.logger.warn("Posting Bsky images without the card's link #{crosspost_config.url}: #{e.message}")
      Post.new(text:, facets:)
    end

    private

    def links_to?(facets, url)
      facets.any? { |facet| facet["features"].any? { |feature| feature["uri"] == url } }
    end
  end
end
