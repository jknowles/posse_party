require "test_helper"

class FindsAccountByOauthStateTest < ActiveSupport::TestCase
  def setup
    @subject = FindsAccountByOauthState.new
    @account = accounts(:user_linkedin_account)
  end

  def test_find_returns_the_account_holding_the_state
    state = GeneratesOauthState.new.generate(@account)

    assert_equal @account, @subject.find(state)
  end

  def test_find_returns_nothing_for_a_blank_state
    GeneratesOauthState.new.generate(@account)

    assert_nil @subject.find("")
    assert_nil @subject.find(nil)
  end

  def test_find_returns_nothing_for_an_unknown_state
    GeneratesOauthState.new.generate(@account)

    assert_nil @subject.find("a-state-nobody-issued")
  end

  def test_find_returns_nothing_once_the_state_has_expired
    state = GeneratesOauthState.new.generate(@account)
    @account.update!(credentials: @account.credentials.merge(
      "renewal_oauth_state_issued_at" => (Now.time - Constants::OAUTH_STATE_TTL_MINUTES.minutes - 1.minute).iso8601
    ))

    assert_nil @subject.find(state)
  end

  def test_find_returns_nothing_for_a_state_stored_without_an_issued_at_timestamp
    @account.update!(credentials: @account.credentials.merge("renewal_oauth_state" => "legacy-state"))

    assert_nil @subject.find("legacy-state")
  end
end
