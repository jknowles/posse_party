require "test_helper"

class CredentialRenewalMailerTest < ActionMailer::TestCase
  def test_renew_linkedin_links_to_the_app_rather_than_straight_to_linkedin
    account = accounts(:user_linkedin_account)

    body = CredentialRenewalMailer.with(account:).renew_linkedin.body.to_s

    assert_includes body, "/accounts/#{account.id}/renew_credentials"
    refute_includes body, "linkedin.com/oauth"
  end

  def test_renew_linkedin_does_not_mint_an_oauth_state
    account = accounts(:user_linkedin_account)

    CredentialRenewalMailer.with(account:).renew_linkedin.body.to_s

    assert_nil account.reload.credentials["renewal_oauth_state"]
  end

  def test_renew_youtube_links_to_the_app_rather_than_straight_to_google
    account = accounts(:user_youtube_account)

    body = CredentialRenewalMailer.with(account:).renew_youtube.body.to_s

    assert_includes body, "/accounts/#{account.id}/renew_credentials"
    refute_includes body, "accounts.google.com"
  end

  def test_renew_youtube_does_not_mint_an_oauth_state
    account = accounts(:user_youtube_account)

    CredentialRenewalMailer.with(account:).renew_youtube.body.to_s

    assert_nil account.reload.credentials["renewal_oauth_state"]
  end
end
