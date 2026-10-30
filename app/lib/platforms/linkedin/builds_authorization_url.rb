class Platforms::Linkedin
  class BuildsAuthorizationUrl
    def build(account, state, scope:)
      oauth_params = {
        response_type: "code",
        client_id: account.credentials["client_id"],
        redirect_uri: Rails.application.routes.url_helpers.credential_renewals_linkedin_url,
        scope: scope,
        state: state
      }

      "https://www.linkedin.com/oauth/v2/authorization?#{oauth_params.to_query}"
    end
  end
end
