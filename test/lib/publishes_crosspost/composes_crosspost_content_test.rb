require "test_helper"

class PublishesCrosspost::ComposesCrosspostContentTest < ActiveSupport::TestCase
  def setup
    @munges_config = PublishesCrosspost::MungesConfig.new
    @subject = PublishesCrosspost::ComposesCrosspostContent.new
    @crosspost = crossposts(:admin_mastodon_crosspost)
    @short_post = {
      url: "https://example.com/shots/1",
      summary: "A short caption",
      format_string: "{{summary}}",
      truncate: true,
      append_url_if_truncated: true,
      append_url_spacer: "\n\n"
    }
  end

  def test_mastodon_appends_url_to_untruncated_post_when_feed_sends_only_append_url_if_truncated
    @crosspost.post.update!(@short_post)

    assert_equal "A short caption\n\nhttps://example.com/shots/1", compose_for_mastodon.string
  end

  def test_mastodon_omits_url_from_untruncated_post_when_feed_sends_append_url_false
    @crosspost.post.update!(@short_post.merge(append_url: false))

    assert_equal "A short caption", compose_for_mastodon.string
  end

  def test_mastodon_platform_override_appends_url_over_post_append_url_false
    @crosspost.post.update!(@short_post.merge(append_url: false, platform_overrides: {"mastodon" => {"append_url" => true}}))

    assert_equal "A short caption\n\nhttps://example.com/shots/1", compose_for_mastodon.string
  end

  private

  def compose_for_mastodon
    @subject.compose(
      @munges_config.munge(@crosspost, Platforms::Mastodon::DEFAULT_CROSSPOST_OPTIONS),
      Platforms::Mastodon::POST_CONSTRAINTS
    )
  end
end
