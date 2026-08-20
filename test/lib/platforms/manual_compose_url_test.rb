require "test_helper"

class ManualComposeUrlTest < ActiveSupport::TestCase
  def test_x_builds_a_prefilled_intent_url
    url = Platforms::X.new.manual_compose_url("Hello, world & then some")

    assert_equal "https://x.com/intent/tweet?text=Hello%2C+world+%26+then+some", url
  end

  def test_platforms_without_a_compose_url_offer_none
    assert_nil Platforms::Linkedin.new.manual_compose_url("Hello, world")
  end
end
