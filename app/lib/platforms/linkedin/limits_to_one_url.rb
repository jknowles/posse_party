class Platforms::Linkedin
  # A LinkedIn post carries at most one URL. When the text already contains one, nothing is appended
  # and the link card, if attached, points at that URL. Otherwise the shared splitter decides as before.
  class LimitsToOneUrl
    Post = Struct.new(:content, :card_url, keyword_init: true)

    # Patterns::URL also matches bare domains ("example.org"); only a link with a scheme counts here
    SCHEMED_URL = %r{\Ahttps?://}i

    def initialize
      @composes_crosspost_content = PublishesCrosspost::ComposesCrosspostContent.new
      @splits_content_from_organic_url = SplitsContentFromOrganicUrl.new
    end

    def limit(crosspost_config, crosspost_content)
      unappended_content = compose(crosspost_config, append_url: false, append_url_if_truncated: false)
      text_url = url_in_text(unappended_content)

      if text_url && crosspost_config.attach_link
        Post.new(content: unappended_content, card_url: text_url)
      else
        content, card_url = @splits_content_from_organic_url.split(crosspost_config, text_url ? unappended_content : crosspost_content)
        Post.new(content: content, card_url: card_url)
      end
    end

    # A post with media has no card, so its one URL stays in the text: the text's own link when it
    # has one, otherwise the appended URL. A card that was asked for and cannot be attached is
    # appended as its URL, so the post still links to the entry.
    def limit_with_media(crosspost_config, crosspost_content)
      unappended_content = compose(crosspost_config, append_url: false, append_url_if_truncated: false)
      content = if url_in_text(unappended_content)
        unappended_content
      elsif crosspost_config.attach_link
        compose(crosspost_config, append_url: true)
      else
        crosspost_content
      end
      Post.new(content:, card_url: nil)
    end

    private

    def compose(crosspost_config, **overrides)
      @composes_crosspost_content.compose(
        CrosspostConfig.new(**crosspost_config.to_h, **overrides),
        Platforms::Linkedin::POST_CONSTRAINTS
      ).string
    end

    def url_in_text(content)
      content.scan(Patterns::URL).find { |url| url.match?(SCHEMED_URL) }
    end
  end
end
