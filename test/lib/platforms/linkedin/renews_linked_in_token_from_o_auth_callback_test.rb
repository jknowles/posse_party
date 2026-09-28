require "test_helper"

class Platforms::Linkedin::RenewsLinkedInTokenFromOAuthCallbackTest < ActiveSupport::TestCase
  def setup
    @exchanges_short_lived_linkedin_token = Mocktail.of_next(Platforms::Linkedin::ExchangesShortLivedLinkedinToken)
    @subject = Platforms::Linkedin::RenewsLinkedInTokenFromOAuthCallback.new
    @account = accounts(:user_linkedin_account)
  end

  def test_renew_exchanges_the_code_when_the_state_is_current
    state = GeneratesOauthState.new.generate(@account)
    stubs { @exchanges_short_lived_linkedin_token.exchange(@account, "auth-code") }.with { Outcome.success }

    result = @subject.renew(code: "auth-code", state:)

    assert result.success?
    assert_equal @account, result.account
  end

  def test_renew_rejects_a_state_that_has_expired
    state = GeneratesOauthState.new.generate(@account)
    @account.update!(credentials: @account.credentials.merge(
      "renewal_oauth_state_issued_at" => (Now.time - Constants::OAUTH_STATE_TTL_MINUTES.minutes - 1.minute).iso8601
    ))

    result = @subject.renew(code: "auth-code", state:)

    refute result.success?
    assert_equal "Invalid state parameter", result.message
  end
end
