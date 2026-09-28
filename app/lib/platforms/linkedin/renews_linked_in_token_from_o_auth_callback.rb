class Platforms::Linkedin
  class RenewsLinkedInTokenFromOAuthCallback
    Result = Struct.new(:success?, :account, :message, keyword_init: true)

    def initialize
      @exchanges_short_lived_linkedin_token = ExchangesShortLivedLinkedinToken.new
      @finds_account_by_oauth_state = FindsAccountByOauthState.new
    end

    def renew(code:, state:)
      if (account = @finds_account_by_oauth_state.find(state))
        if (token_result = @exchanges_short_lived_linkedin_token.exchange(account, code)).success?
          Result.new(success?: true, account: account)
        else
          Result.new(success?: false, account: account, message: token_result.message)
        end
      else
        Result.new(success?: false, message: "Invalid state parameter")
      end
    end
  end
end
