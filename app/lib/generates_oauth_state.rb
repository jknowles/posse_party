class GeneratesOauthState
  def initialize
    @determines_oauth_state_freshness = DeterminesOauthStateFreshness.new
  end

  def generate(account)
    unexpired_state(account) || mint_state(account)
  end

  private

  def unexpired_state(account)
    state = account.credentials["renewal_oauth_state"].presence

    state if state && @determines_oauth_state_freshness.fresh?(account.credentials)
  end

  def mint_state(account)
    SecureRandom.hex(16).tap do |state|
      account.update!(
        credentials: account.credentials.merge(
          "renewal_oauth_state" => state,
          "renewal_oauth_state_issued_at" => Now.time.iso8601
        )
      )
    end
  end
end
