require "test_helper"

class Platforms::Bsky::AttachesWebCardTest < ActiveSupport::TestCase
  def test_uses_summary_when_og_description_is_missing
    subject = Platforms::Bsky::AttachesWebCard.new
    crosspost_config = CrosspostConfig.new(
      url: "https://example.com/posts/123",
      title: "A Consistent Title",
      summary: "A consistent description",
      og_title: nil,
      og_description: nil,
      og_image: nil
    )

    result = subject.attach!(crosspost_config, nil)

    assert_equal "app.bsky.embed.external", result["$type"]
    assert_equal "https://example.com/posts/123", result["external"]["uri"]
    assert_equal "A Consistent Title", result["external"]["title"]
    assert_equal "A consistent description", result["external"]["description"]
  end

  def test_description_key_is_present_as_empty_string_when_blank
    # Bluesky's app.bsky.embed.external#external lexicon requires the
    # "description" key to be present. An empty string is valid; a missing key
    # is rejected by the PDS. Ensure we always send the key.
    subject = Platforms::Bsky::AttachesWebCard.new
    crosspost_config = CrosspostConfig.new(
      url: "https://example.com/posts/123",
      title: "A Consistent Title",
      summary: nil,
      og_title: nil,
      og_description: nil,
      og_image: nil
    )

    result = subject.attach!(crosspost_config, nil)

    assert result["external"].key?("description"), "expected description key to be present"
    assert_equal "", result["external"]["description"]
  end

  def test_description_key_is_present_as_empty_string_when_empty
    subject = Platforms::Bsky::AttachesWebCard.new
    crosspost_config = CrosspostConfig.new(
      url: "https://example.com/posts/123",
      title: "A Consistent Title",
      summary: "",
      og_title: nil,
      og_description: "",
      og_image: nil
    )

    result = subject.attach!(crosspost_config, nil)

    assert result["external"].key?("description"), "expected description key to be present"
    assert_equal "", result["external"]["description"]
  end
end
