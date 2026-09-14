class DeterminesOauthStateFreshness
  def fresh?(credentials)
    issued_at = parse_time(credentials["renewal_oauth_state_issued_at"])

    issued_at.present? && issued_at > Now.ago(Constants::OAUTH_STATE_TTL_MINUTES.minutes)
  end

  private

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
