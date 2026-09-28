class FindsAccountByOauthState
  def initialize
    @determines_oauth_state_freshness = DeterminesOauthStateFreshness.new
  end

  def find(state)
    return if state.blank?

    account = Account.where("credentials ->> 'renewal_oauth_state' = ?", state).first
    account if account && @determines_oauth_state_freshness.fresh?(account.credentials)
  end
end
