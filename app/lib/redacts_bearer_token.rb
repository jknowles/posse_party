# Net::HTTP quotes a header it refuses (one holding a line break, say) in its error message, so an
# exception raised while building a request can carry the access token. The quoted value escapes
# its own quotes and backslashes, so the match runs to the first unescaped quote.
class RedactsBearerToken
  def redact(message)
    message.gsub(/Bearer (?:\\.|[^"\\])*/, "Bearer [FILTERED]")
  end
end
