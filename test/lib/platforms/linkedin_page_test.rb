require "test_helper"

class Platforms::LinkedinPageTest < ActiveSupport::TestCase
  def test_publishes_as_the_organization
    syndicates_linkedin_post = Mocktail.of_next(Platforms::Linkedin::SyndicatesLinkedinPost)
    subject = Platforms::LinkedinPage.new
    stubs {
      syndicates_linkedin_post.syndicate!(crosspost: :some_crosspost, crosspost_config: :some_config, crosspost_content: "Hello", author_credential: "organization_urn")
    }.with { :some_result }

    assert_equal :some_result, subject.publish!(:some_crosspost, :some_config, PublishesCrosspost::IdentifiesPatternRanges::Result.new("Hello", []))
  end

  def test_finishes_a_processing_video_as_the_organization
    syndicates_linkedin_post = Mocktail.of_next(Platforms::Linkedin::SyndicatesLinkedinPost)
    subject = Platforms::LinkedinPage.new
    stubs { syndicates_linkedin_post.finish!(:some_crosspost, author_credential: "organization_urn") }.with { :some_result }

    assert subject.finishable?
    assert_equal :some_result, subject.finish!(:some_crosspost)
  end

  def test_renewal_url_requests_the_organization_posting_scope
    builds_authorization_url = Mocktail.of_next(Platforms::Linkedin::BuildsAuthorizationUrl)
    subject = Platforms::LinkedinPage.new
    stubs { builds_authorization_url.build(:some_account, "STATE123", scope: "w_organization_social") }.with { :some_url }

    assert_equal :some_url, subject.renewal_url(:some_account, "STATE123")
  end

  def test_renewal_reminders_use_the_linkedin_reminder
    potentially_tells = Mocktail.of_next(Platforms::Linkedin::PotentiallyTellsUserToRenewLinkedinAccessToken)
    subject = Platforms::LinkedinPage.new

    subject.renew!(:some_account)

    verify { potentially_tells.potentially_tell(:some_account) }
  end
end
