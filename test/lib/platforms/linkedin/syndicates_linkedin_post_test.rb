require "test_helper"

class Platforms::Linkedin::SyndicatesLinkedinPostTest < ActiveSupport::TestCase
  URL = "https://example.com/social/map/"

  def setup
    @uploads_media = Mocktail.of_next(Platforms::Linkedin::UploadsMedia)
    @limits_to_one_url = Mocktail.of_next(Platforms::Linkedin::LimitsToOneUrl)
    @publishes_post = Mocktail.of_next(Platforms::Linkedin::PublishesPost)
    @subject = Platforms::Linkedin::SyndicatesLinkedinPost.new
    @crosspost = Crosspost.create!(post: posts(:user_post), account: accounts(:user_linkedin_account), status: "wip")
    @config = CrosspostConfig.new(url: URL)
  end

  def test_posts_uploaded_images_with_one_url_in_the_text_and_no_card
    media = [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A loop")]
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123") }.with { media }
    stubs { @limits_to_one_url.limit_with_media(@config, "A map at https://maps.example.com/ (2024)\n\n#{URL}") }.with {
      Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map at https://maps.example.com/ (2024)", card_url: nil)
    }
    stubs {
      @publishes_post.publish("A map at https://maps.example.com/ \\(2024\\)", @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123", image_urn: nil, url: nil, media:)
    }.with { published("urn:li:share:1") }

    result = @subject.syndicate!(@crosspost, @config, "A map at https://maps.example.com/ (2024)\n\n#{URL}")

    assert result.success?
    assert_equal "published", @crosspost.reload.status
    assert_equal "urn:li:share:1", @crosspost.remote_id
    assert_equal "A map at https://maps.example.com/ (2024)", @crosspost.content
    verify_never_called { @limits_to_one_url.limit }
  end

  def test_without_media_posts_the_link_card_as_before
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123") }.with { [] }
    stubs { @limits_to_one_url.limit(@config, "A map") }.with { Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map", card_url: URL) }
    stubs {
      @publishes_post.publish("A map", @config, access_token: "linkedin-access-token", person_urn: "urn:li:person:TEST123", image_urn: nil, url: URL, media: [])
    }.with { published("urn:li:share:2") }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_equal "urn:li:share:2", @crosspost.reload.remote_id
  end

  private

  def published(urn)
    Platforms::Linkedin::PublishesPost::Result.new(true, urn, "https://www.linkedin.com/feed/update/#{urn}/")
  end
end
