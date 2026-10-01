require "test_helper"

class Platforms::Bsky::KeepsLinkWithMediaTest < ActiveSupport::TestCase
  URL = "https://example.com/social/map/"

  def setup
    @subject = Platforms::Bsky::KeepsLinkWithMedia.new
  end

  def test_appends_the_link_a_card_would_have_carried
    post = @subject.keep(config(content: "A map", attach_link: true), "A map", [])

    assert_equal "A map 🔗", post.text
    assert_equal [link_facet(6, 10)], post.facets
  end

  def test_trims_text_at_the_limit_to_make_room_for_the_link
    content = "word " * 60

    post = @subject.keep(config(content:, attach_link: true), content.strip, [])

    assert_equal "#{"word " * 58}word... 🔗", post.text
    assert_operator post.text.grapheme_clusters.size, :<=, 300
    assert_equal [link_facet(298, 302)], post.facets
  end

  def test_leaves_text_that_already_links_to_the_url
    facets = [link_facet(0, 31)]

    post = @subject.keep(config(content: URL, attach_link: true), URL, facets)

    assert_equal URL, post.text
    assert_equal facets, post.facets
  end

  def test_leaves_a_post_that_asked_for_no_card
    post = @subject.keep(config(content: "A map", attach_link: false), "A map", [])

    assert_equal "A map", post.text
    assert_equal [], post.facets
  end

  private

  def config(content:, attach_link:)
    CrosspostConfig.new(**Platforms::Bsky::DEFAULT_CROSSPOST_OPTIONS, url: URL, content:, format_string: "{{content}}", attach_link:)
  end

  def link_facet(byte_start, byte_end)
    {
      "$type" => "app.bsky.richtext.facet",
      "index" => {"byteStart" => byte_start, "byteEnd" => byte_end},
      "features" => [{"uri" => URL, "$type" => "app.bsky.richtext.facet#link"}]
    }
  end
end
