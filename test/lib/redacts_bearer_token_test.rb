require "test_helper"

class RedactsBearerTokenTest < ActiveSupport::TestCase
  def test_replaces_the_token_net_http_quotes_in_a_header_error
    message = %(header Authorization has field value "Bearer a warning\\nSECRET-TOKEN-123", this cannot include CR/LF)

    assert_equal %(header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF), RedactsBearerToken.new.redact(message)
  end

  def test_replaces_a_token_captured_with_a_quote_in_front_of_it
    message = %(header Authorization has field value "Bearer warn \\"x\\"\\nSECRET-TOKEN-123", this cannot include CR/LF)

    assert_equal %(header Authorization has field value "Bearer [FILTERED]", this cannot include CR/LF), RedactsBearerToken.new.redact(message)
  end

  def test_leaves_a_message_without_a_token_alone
    assert_equal "Net::ReadTimeout", RedactsBearerToken.new.redact("Net::ReadTimeout")
  end
end
