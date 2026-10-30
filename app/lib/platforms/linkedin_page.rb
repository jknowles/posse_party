module Platforms
  # Posts to a LinkedIn Company Page through the Community Management API. It shares
  # Platforms::Linkedin's helpers and OAuth callback, differing only in the author
  # (an organization URN) and the scope it requests.
  class LinkedinPage < Base
    TAG = "linkedin_page"
    LABEL = "LinkedIn Page"

    REQUIRED_CREDENTIALS = %w[client_id access_token client_secret organization_urn].freeze
    CREDENTIAL_LABELS = {
      "organization_urn" => "Organization URN"
    }.freeze

    POST_CONSTRAINTS = Platforms::Linkedin::POST_CONSTRAINTS
    DEFAULT_CROSSPOST_OPTIONS = Platforms::Linkedin::DEFAULT_CROSSPOST_OPTIONS

    RENEWABLE = true
    RENEWAL_URL_SUPPORTED = true
    IRRELEVANT_CONFIG_OPTIONS = Platforms::Linkedin::IRRELEVANT_CONFIG_OPTIONS

    def initialize
      @syndicates_linkedin_post = Platforms::Linkedin::SyndicatesLinkedinPost.new
      @potentially_tells_user_to_renew_linkedin_access_token = Platforms::Linkedin::PotentiallyTellsUserToRenewLinkedinAccessToken.new
      @builds_authorization_url = Platforms::Linkedin::BuildsAuthorizationUrl.new
    end

    def setup_docs_available?
      true
    end

    def publish!(crosspost, crosspost_config, crosspost_content)
      @syndicates_linkedin_post.syndicate!(crosspost:, crosspost_config:, crosspost_content: crosspost_content.string, author_credential: "organization_urn")
    end

    def renew!(account)
      @potentially_tells_user_to_renew_linkedin_access_token.potentially_tell(account)
    end

    def renewal_url(account, state)
      @builds_authorization_url.build(account, state, scope: "w_organization_social")
    end
  end
end
