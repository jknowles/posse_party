require "test_helper"

class Platforms::Linkedin::LimitsToOneUrlTest < ActiveSupport::TestCase
  PERMALINK = "https://example.com/shots/1"

  def setup
    @subject = Platforms::Linkedin::LimitsToOneUrl.new
  end

  def test_card_uses_a_url_in_the_middle_of_the_text_and_nothing_is_appended
    crosspost_config = config(summary: "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", append_url: true)

    post = @subject.limit(crosspost_config, compose(crosspost_config))

    assert_equal "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", post.content
    assert_equal "https://cog-demo.civilytics.org", post.card_url
  end

  def test_card_uses_a_url_at_the_end_of_the_text_and_keeps_it_in_the_text
    crosspost_config = config(summary: "Across 56 published years: https://cog-demo.civilytics.org/")

    post = @subject.limit(crosspost_config, compose(crosspost_config))

    assert_equal "Across 56 published years: https://cog-demo.civilytics.org/", post.content
    assert_equal "https://cog-demo.civilytics.org", post.card_url
  end

  def test_card_uses_the_entry_url_when_the_text_has_no_url
    crosspost_config = config(summary: "A short caption", append_url: true, append_url_spacer: "\n\n")

    post = @subject.limit(crosspost_config, compose(crosspost_config))

    assert_equal "A short caption\n\n#{PERMALINK}", post.content
    assert_equal PERMALINK, post.card_url
  end

  def test_a_domain_without_a_scheme_does_not_count_as_the_texts_url
    crosspost_config = config(summary: "I moved my notes to example.org last year")

    post = @subject.limit(crosspost_config, compose(crosspost_config))

    assert_equal "I moved my notes to example.org last year", post.content
    assert_equal PERMALINK, post.card_url
  end

  def test_without_attach_link_a_url_in_the_middle_gets_no_card_and_nothing_is_appended
    crosspost_config = config(summary: "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", attach_link: false, append_url: true)

    post = @subject.limit(crosspost_config, compose(crosspost_config))

    assert_equal "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", post.content
    assert_nil post.card_url
  end

  def test_with_media_a_url_in_the_text_is_the_only_url
    crosspost_config = config(summary: "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", attach_link: false, append_url: true, append_url_spacer: "\n\n")

    post = @subject.limit_with_media(crosspost_config, compose(crosspost_config))

    assert_equal "The explorer at https://cog-demo.civilytics.org/ covers 56 years.", post.content
    assert_nil post.card_url
  end

  def test_with_media_the_appended_url_stays_in_the_text
    crosspost_config = config(summary: "A short caption", attach_link: false, append_url: true, append_url_spacer: "\n\n")

    post = @subject.limit_with_media(crosspost_config, compose(crosspost_config))

    assert_equal "A short caption\n\n#{PERMALINK}", post.content
    assert_nil post.card_url
  end

  def test_with_media_a_card_that_cannot_be_attached_becomes_an_appended_url
    crosspost_config = config(summary: "A short caption", append_url_spacer: "\n\n")

    post = @subject.limit_with_media(crosspost_config, compose(crosspost_config))

    assert_equal "A short caption\n\n#{PERMALINK}", post.content
    assert_nil post.card_url
  end

  def test_with_media_and_no_link_asked_for_the_text_has_no_url
    crosspost_config = config(summary: "A short caption", attach_link: false)

    post = @subject.limit_with_media(crosspost_config, compose(crosspost_config))

    assert_equal "A short caption", post.content
  end

  private

  def config(**overrides)
    CrosspostConfig.new(**Platforms::Linkedin::DEFAULT_CROSSPOST_OPTIONS.merge(url: PERMALINK, format_string: "{{summary}}").merge(overrides))
  end

  def compose(crosspost_config)
    PublishesCrosspost::ComposesCrosspostContent.new.compose(crosspost_config, Platforms::Linkedin::POST_CONSTRAINTS).string
  end
end
