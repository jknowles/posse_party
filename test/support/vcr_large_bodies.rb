# A video's bytes are already in test/fixtures/files/media, so a cassette keeps only how many
# there were. Tests that upload video match requests without their bodies and assert on what
# WebMock saw instead. A cassette that matches on :body keeps its bodies, or it could not match.
VCR.configure do |config|
  config.before_record do |interaction, cassette|
    next if cassette.match_requests_on.include?(:body)

    size = interaction.request.body.to_s.bytesize
    interaction.request.body = "[#{size} bytes, not kept in the cassette]" if size > 64 * 1024
  end
end
