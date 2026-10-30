require "test_helper"

class Platforms::Linkedin::BuildsAuthorizationUrlTest < ActiveSupport::TestCase
  def test_builds_the_oauth_url_for_the_given_scope
    url = Platforms::Linkedin::BuildsAuthorizationUrl.new.build(accounts(:user_linkedin_page_account), "STATE123", scope: "w_organization_social")

    uri = URI.parse(url)
    assert_equal "https://www.linkedin.com/oauth/v2/authorization", "#{uri.scheme}://#{uri.host}#{uri.path}"
    assert_equal({
      "response_type" => "code",
      "client_id" => "linkedin-page-client-id",
      "redirect_uri" => Rails.application.routes.url_helpers.credential_renewals_linkedin_url,
      "scope" => "w_organization_social",
      "state" => "STATE123"
    }, Rack::Utils.parse_query(uri.query))
  end
end
