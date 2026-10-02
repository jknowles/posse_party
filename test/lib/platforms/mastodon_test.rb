require "test_helper"

class Platforms::MastodonTest < ActiveSupport::TestCase
  def setup
    @syndicates_mastodon_post = Mocktail.of_next(Platforms::Mastodon::SyndicatesMastodonPost)
    @subject = Platforms::Mastodon.new
    @crosspost = crossposts(:admin_mastodon_crosspost)
  end

  def test_publishes_with_the_crosspost_config
    config = CrosspostConfig.new(media: [])
    stubs { @syndicates_mastodon_post.syndicate!(@crosspost, config, "A map") }.with { PublishesCrosspost::Result.new(success?: true) }

    result = @subject.publish!(@crosspost, config, PublishesCrosspost::IdentifiesPatternRanges::Result.new("A map", []))

    assert result.success?
  end

  def test_finishes_a_post_left_waiting_on_media
    stubs { @syndicates_mastodon_post.finish!(@crosspost) }.with { PublishesCrosspost::Result.new(success?: true) }

    assert @subject.finishable?
    assert @subject.finish!(@crosspost).success?
  end
end
