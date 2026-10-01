class Platforms::Linkedin
  # Net::HTTP quotes a header it refuses (one holding a line break, say) in its error message, so an
  # exception raised while building a request can carry the access token
  class RedactsBearerToken
    def redact(message)
      message.gsub(/Bearer [^"]*/, "Bearer [FILTERED]")
    end
  end
end
