require "test_helper"

class GeneratesOauthStateTest < ActiveSupport::TestCase
  def test_generate_updates_credentials_even_with_stale_disabled_feed_ids
    account = accounts(:user_youtube_account)
    # Simulate historical bad data: a feed id from another user persisted on the account
    foreign_feed_id = feeds(:admin_feed).id
    account.update_columns(disabled_feed_ids: [foreign_feed_id])

    state = nil
    assert_nothing_raised do
      state = GeneratesOauthState.new.generate(account)
    end

    assert_match(/\A[0-9a-f]{32}\z/, state)
    assert_equal state, account.reload.credentials["renewal_oauth_state"]
  end

  def test_generate_reuses_an_unexpired_state
    account = accounts(:user_linkedin_account)
    subject = GeneratesOauthState.new

    first = subject.generate(account)
    second = subject.generate(account)

    assert_equal first, second
    assert_equal first, account.reload.credentials["renewal_oauth_state"]
  end

  def test_generate_mints_a_new_state_once_the_previous_one_expires
    account = accounts(:user_linkedin_account)
    subject = GeneratesOauthState.new
    first = subject.generate(account)

    account.update!(credentials: account.credentials.merge(
      "renewal_oauth_state_issued_at" => (Now.time - Constants::OAUTH_STATE_TTL_MINUTES.minutes - 1.minute).iso8601
    ))
    second = subject.generate(account)

    refute_equal first, second
    assert_equal second, account.reload.credentials["renewal_oauth_state"]
  end

  def test_generate_replaces_a_state_stored_without_an_issued_at_timestamp
    account = accounts(:user_linkedin_account)
    account.update!(credentials: account.credentials.merge("renewal_oauth_state" => "legacy-state"))

    state = GeneratesOauthState.new.generate(account)

    refute_equal "legacy-state", state
    assert_equal state, account.reload.credentials["renewal_oauth_state"]
  end
end
