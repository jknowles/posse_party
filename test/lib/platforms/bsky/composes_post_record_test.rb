require "test_helper"

class Platforms::Bsky::ComposesPostRecordTest < ActiveSupport::TestCase
  Session = Struct.new(:pds, :access_token, :did, keyword_init: true)
  URL = "https://example.com/social/map/"
  CARD = {"$type" => "app.bsky.embed.external", "external" => {"uri" => URL, "title" => "A map", "description" => ""}}
  IMAGES = [{"alt" => "An orange square", "image" => "blob-1"}]

  def setup
    @uploads_bsky_media = Mocktail.of_next(Platforms::Bsky::UploadsBskyMedia)
    @keeps_link_with_media = Mocktail.of_next(Platforms::Bsky::KeepsLinkWithMedia)
    @attaches_web_card = Mocktail.of_next(Platforms::Bsky::AttachesWebCard)
    @subject = Platforms::Bsky::ComposesPostRecord.new
    @crosspost = crossposts(:admin_bsky_crosspost)
    @record_manager = Bskyrb::RecordManager.new(Session.new(pds: "https://bsky.social", access_token: "jwt", did: "did:plc:example"))
    Now.override!(Time.zone.parse("2026-10-06 14:00:00 UTC"), freeze: true)
  end

  def test_posts_uploaded_images_in_place_of_the_card_and_keeps_the_link
    config = CrosspostConfig.new(url: URL, attach_link: true)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { IMAGES }
    stubs { @keeps_link_with_media.keep(config, "A map", []) }.with { Platforms::Bsky::KeepsLinkWithMedia::Post.new(text: "A map 🔗", facets: ["link facet"]) }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal "A map 🔗", composed.text
    assert_equal record("A map 🔗", ["link facet"], {"$type" => "app.bsky.embed.images", "images" => IMAGES}), composed.record
    verify_never_called { @attaches_web_card.attach! }
  end

  def test_without_media_attaches_the_card_as_before
    config = CrosspostConfig.new(url: URL, attach_link: true)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { [] }
    stubs { @attaches_web_card.attach!(config, @record_manager) }.with { CARD }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal "A map", composed.text
    assert_equal record("A map", [], CARD), composed.record
    verify_never_called { @keeps_link_with_media.keep }
  end

  def test_without_media_or_a_card_posts_the_text_alone
    config = CrosspostConfig.new(url: URL, attach_link: false)
    stubs { @uploads_bsky_media.upload(@crosspost, config, @record_manager) }.with { [] }

    composed = @subject.compose(@crosspost, config, text: "A map", facets: [], record_manager: @record_manager)

    assert_equal record("A map", [], nil), composed.record
  end

  private

  def record(text, facets, embed)
    {
      "collection" => "app.bsky.feed.post",
      "$type" => "app.bsky.feed.post",
      "repo" => "did:plc:example",
      "record" => {
        "$type" => "app.bsky.feed.post",
        "createdAt" => "2026-10-06T14:00:00.000Z",
        "text" => text,
        "facets" => facets,
        "embed" => embed
      }.compact
    }
  end
end
