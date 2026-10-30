require "test_helper"

class Platforms::Linkedin::SyndicatesLinkedinPostTest < ActiveSupport::TestCase
  def test_posts_as_the_author_named_by_the_given_credential
    initiates_image_upload = Mocktail.of_next(Platforms::Linkedin::InitiatesImageUpload)
    uploads_image = Mocktail.of_next(Platforms::Linkedin::UploadsImage)
    publishes_post = Mocktail.of_next(Platforms::Linkedin::PublishesPost)
    subject = Platforms::Linkedin::SyndicatesLinkedinPost.new
    crosspost = Crosspost.create!(post: posts(:user_post), account: accounts(:user_linkedin_page_account), status: "wip")
    crosspost_config = CrosspostConfig.new(
      url: "https://user.example.com/posts/1",
      attach_link: true,
      og_image: "https://user.example.com/card.jpg"
    )

    stubs {
      initiates_image_upload.initiate(access_token: "linkedin-page-access-token", author_urn: "urn:li:organization:TEST456")
    }.with {
      Platforms::Linkedin::InitiatesImageUpload::Result.new(success?: true, upload_url: "https://upload.example.com", image_urn: "urn:li:image:IMG1")
    }
    stubs {
      uploads_image.upload("https://user.example.com/card.jpg", "https://upload.example.com", access_token: "linkedin-page-access-token")
    }.with { Outcome.success }
    stubs {
      publishes_post.publish(
        "Hello from the Page",
        crosspost_config,
        access_token: "linkedin-page-access-token",
        author_urn: "urn:li:organization:TEST456",
        image_urn: "urn:li:image:IMG1",
        url: "https://user.example.com/posts/1"
      )
    }.with {
      Platforms::Linkedin::PublishesPost::Result.new(success?: true, post_urn: "urn:li:share:1", url: "https://www.linkedin.com/feed/update/urn:li:share:1/")
    }

    result = subject.syndicate!(
      crosspost:,
      crosspost_config:,
      crosspost_content: "Hello from the Page",
      author_credential: "organization_urn"
    )

    assert result.success?
    assert_equal "published", crosspost.reload.status
    assert_equal "urn:li:share:1", crosspost.remote_id
  end

  def test_fails_when_the_author_credential_is_missing
    subject = Platforms::Linkedin::SyndicatesLinkedinPost.new
    crosspost = Crosspost.create!(post: posts(:user_post), account: accounts(:user_linkedin_account), status: "wip")

    result = subject.syndicate!(
      crosspost:,
      crosspost_config: CrosspostConfig.new,
      crosspost_content: "Hello",
      author_credential: "organization_urn"
    )

    refute result.success?
    assert_equal "Missing organization_urn credential", result.message
  end
end
