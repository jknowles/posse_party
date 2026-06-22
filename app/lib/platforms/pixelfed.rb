module Platforms
  class Pixelfed < Base
    TAG = "pixelfed"
    LABEL = "Pixelfed"

    # Pixelfed implements the Mastodon client API, so authentication is the same
    # as Mastodon: an instance base URL plus a personal access token.
    REQUIRED_CREDENTIALS = %w[base_url access_token].freeze

    # Pixelfed's default caption limit is 500 characters (instance-configurable).
    POST_CONSTRAINTS = Constants::DEFAULT_POST_CONSTRAINTS.merge(
      character_limit: 500
    ).freeze

    # Pixelfed is photo-first, so the caption is just the post content and we
    # append a link back to the original post (mirroring the Instagram path).
    DEFAULT_CROSSPOST_OPTIONS = Platforms::DEFAULT_CROSSPOST_OPTIONS.merge(
      format_string: "{{content}}",
      append_url: true,
      append_url_if_truncated: true,
      append_url_spacer: "\n\nSee the full post at:\n",
      attach_link: false # not supported
    ).freeze

    IRRELEVANT_CONFIG_OPTIONS = [:append_url_label, :attach_link, :og_image].freeze
    EMBED_SUPPORTED = true

    def initialize
      @syndicates_pixelfed_post = SyndicatesPixelfedPost.new
    end

    def setup_docs_available?
      true
    end

    def publish!(crosspost, crosspost_config, crosspost_content)
      @syndicates_pixelfed_post.syndicate!(crosspost, crosspost_content.string)
    end

    def embed_html(crosspost)
      return nil unless crosspost.status == "published" && crosspost.url.present?

      # Pixelfed embeds use an iframe, like Mastodon
      <<~HTML
        <iframe src="#{crosspost.url}/embed"
                class="pixelfed-embed"
                style="max-width: 100%; border: 0"
                width="400"
                allowfullscreen="allowfullscreen">
        </iframe>
        <script src="#{crosspost.account.credentials["base_url"]}/embed.js" async="async"></script>
      HTML
    end
  end
end
