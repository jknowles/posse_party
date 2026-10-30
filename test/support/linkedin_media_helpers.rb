# Shared by the recorded media tests of both LinkedIn targets (profile and Company Page)
module LinkedinMediaHelpers
  # A commit, not a branch, so a re-recording fetches the same bytes these cassettes hold
  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/914ff8332cb956c77ac45a0dd182dc8a47f862a7/test/fixtures/files/media"

  # Served from test/fixtures by WebMock, which VCR leaves out of the cassette, so a recording
  # needs nothing pushed first
  VIDEO_BASE = "https://media.example/posse-party"

  def linkedin_crosspost_with_media(post_url, media, platform_tag:, credentials:, platform_media: media, overrides: {})
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag:, label: "LinkedIn", credentials: vcr_secrets(credentials))
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {platform_tag => {media: platform_media, append_url: true, append_url_spacer: "\n\n", attach_link: false}.merge(overrides)}
    }
    stub_request(:get, feed_url).to_return(status: 200, body: <<~XML)
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
        <title>Test Feed</title>
        <id>#{feed_url}</id>
        <updated>2026-10-01T00:00:00Z</updated>
        <entry>
          <title>Media test</title>
          <id>#{post_url}</id>
          <published>2026-10-01T00:00:00Z</published>
          <updated>2026-10-01T00:00:00Z</updated>
          <link rel="alternate" href="#{post_url}"/>
          <posse:post><![CDATA[#{posse.to_json}]]></posse:post>
        </entry>
      </feed>
    XML
    FetchesFeed.new.fetch!(user.feeds.create!(url: feed_url, label: "media test"), cache: false)
    Crosspost.find_by!(post: Post.find_by!(remote_id: post_url)).tap { |crosspost| crosspost.update!(status: "wip") }
  end

  def assert_published_with_media(crosspost)
    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_match(/\Aurn:li:(share|ugcPost):/, crosspost.remote_id)
    assert_nil crosspost.metadata["media_fallback"]
  end

  # The post carries its media and, as its only link, the entry's URL appended to the text
  def assert_linkedin_post(post_url:, author:, &content_matches)
    assert_requested(:post, "https://api.linkedin.com/rest/posts") { |request|
      body = JSON.parse(request.body, symbolize_names: true)
      body[:author] == author &&
        body[:commentary] == "PosseParty media test \\(deleted after recording\\)\n\n#{post_url}" &&
        content_matches.call(body[:content])
    }
  end

  def stub_fixture(name, content_type)
    stub_request(:get, "#{VIDEO_BASE}/#{name}").to_return(status: 200, body: file_fixture("media/#{name}").binread, headers: {"Content-Type" => content_type})
  end
end
