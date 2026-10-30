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
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123") }.with { media }
    stubs { @limits_to_one_url.limit_with_media(@config, "A map at https://maps.example.com/ (2024)\n\n#{URL}") }.with {
      Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map at https://maps.example.com/ (2024)", card_url: nil)
    }
    stubs {
      @publishes_post.publish("A map at https://maps.example.com/ \\(2024\\)", @config, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123", image_urn: nil, url: nil, media:)
    }.with { published("urn:li:share:1") }

    result = @subject.syndicate!(crosspost: @crosspost, crosspost_config: @config, crosspost_content: "A map at https://maps.example.com/ (2024)\n\n#{URL}", author_credential: "person_urn")

    assert result.success?
    assert_equal "published", @crosspost.reload.status
    assert_equal "urn:li:share:1", @crosspost.remote_id
    assert_equal "A map at https://maps.example.com/ (2024)", @crosspost.content
    verify_never_called { @limits_to_one_url.limit }
  end

  def test_without_media_posts_the_link_card_as_before
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123") }.with { [] }
    stubs { @limits_to_one_url.limit(@config, "A map") }.with { Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map", card_url: URL) }
    stubs {
      @publishes_post.publish("A map", @config, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123", image_urn: nil, url: URL, media: [])
    }.with { published("urn:li:share:2") }

    result = @subject.syndicate!(crosspost: @crosspost, crosspost_config: @config, crosspost_content: "A map", author_credential: "person_urn")

    assert result.success?
    assert_equal "urn:li:share:2", @crosspost.reload.remote_id
  end

  def test_a_video_still_processing_is_kept_to_post_later
    media = [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:video:1", processing: true)]
    stubs { @uploads_media.upload(@crosspost, @config, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123") }.with { media }
    stubs { @limits_to_one_url.limit_with_media(@config, "A loop (2024)\n\n#{URL}") }.with {
      Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A loop (2024)\n\n#{URL}", card_url: nil)
    }

    result = @subject.syndicate!(crosspost: @crosspost, crosspost_config: @config, crosspost_content: "A loop (2024)\n\n#{URL}", author_credential: "person_urn")

    assert result.success?
    assert result.needs_to_finish?
    assert_equal({"urn" => "urn:li:video:1", "content" => "A loop (2024)\n\n#{URL}"}, @crosspost.reload.metadata["linkedin_video"])
    verify_never_called { @publishes_post.publish }
  end

  def test_finishing_posts_the_kept_video_once_it_is_ready
    keep_video("A loop (2024)\n\n#{URL}")
    media = [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:video:1", processing: false)]
    stubs { @uploads_media.finish(@crosspost, "urn:li:video:1", access_token: "linkedin-access-token") }.with { media }
    stubs {
      @publishes_post.publish("A loop \\(2024\\)\n\n#{URL}", CrosspostConfig.new, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123", image_urn: nil, url: nil, media:)
    }.with { published("urn:li:share:3") }

    result = @subject.finish!(@crosspost, author_credential: "person_urn")

    assert result.success?
    assert_not result.needs_to_finish?
    assert_equal "urn:li:share:3", @crosspost.reload.remote_id
    assert_equal "A loop (2024)\n\n#{URL}", @crosspost.content
  end

  def test_finishing_asks_again_while_the_video_is_processing
    keep_video("A loop")
    stubs { @uploads_media.finish(@crosspost, "urn:li:video:1", access_token: "linkedin-access-token") }.with {
      [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:video:1", processing: true)]
    }

    result = @subject.finish!(@crosspost, author_credential: "person_urn")

    assert result.needs_to_finish?
    verify_never_called { @publishes_post.publish }
  end

  def test_finishing_posts_the_commentary_alone_when_the_video_failed
    keep_video("A loop\n\n#{URL}")
    stubs { @uploads_media.finish(@crosspost, "urn:li:video:1", access_token: "linkedin-access-token") }.with { [] }
    stubs {
      @publishes_post.publish("A loop\n\n#{URL}", CrosspostConfig.new, access_token: "linkedin-access-token", author_urn: "urn:li:person:TEST123", image_urn: nil, url: nil, media: [])
    }.with { published("urn:li:share:4") }

    result = @subject.finish!(@crosspost, author_credential: "person_urn")

    assert result.success?
    assert_equal "urn:li:share:4", @crosspost.reload.remote_id
  end

  def test_finishing_without_a_kept_video_fails
    result = @subject.finish!(@crosspost, author_credential: "person_urn")

    assert_not result.success?
    assert_equal "No LinkedIn video is waiting to be posted", result.message
  end

  def test_posts_and_uploads_as_the_author_named_by_the_given_credential
    crosspost = Crosspost.create!(post: posts(:user_post), account: accounts(:user_linkedin_page_account), status: "wip")
    media = [Platforms::Linkedin::UploadsMedia::Uploaded.new(urn: "urn:li:image:1", alt: "A map")]
    stubs { @uploads_media.upload(crosspost, @config, access_token: "linkedin-page-access-token", author_urn: "urn:li:organization:TEST456") }.with { media }
    stubs { @limits_to_one_url.limit_with_media(@config, "A map") }.with { Platforms::Linkedin::LimitsToOneUrl::Post.new(content: "A map", card_url: nil) }
    stubs {
      @publishes_post.publish("A map", @config, access_token: "linkedin-page-access-token", author_urn: "urn:li:organization:TEST456", image_urn: nil, url: nil, media:)
    }.with { published("urn:li:share:5") }

    result = @subject.syndicate!(crosspost:, crosspost_config: @config, crosspost_content: "A map", author_credential: "organization_urn")

    assert result.success?
    assert_equal "urn:li:share:5", crosspost.reload.remote_id
  end

  def test_fails_when_the_author_credential_is_missing
    result = @subject.syndicate!(crosspost: @crosspost, crosspost_config: @config, crosspost_content: "A map", author_credential: "organization_urn")

    assert_not result.success?
    assert_equal "Missing organization_urn credential", result.message
    verify_never_called { @uploads_media.upload }
  end

  private

  def published(urn)
    Platforms::Linkedin::PublishesPost::Result.new(true, urn, "https://www.linkedin.com/feed/update/#{urn}/")
  end

  def keep_video(content)
    @crosspost.update!(metadata: {"linkedin_video" => {"urn" => "urn:li:video:1", "content" => content}})
  end
end
