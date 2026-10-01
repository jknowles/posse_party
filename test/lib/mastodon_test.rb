require "test_helper"

class MastodonTest < ActiveSupport::TestCase
  def test_syndication
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-01-28-justin.searls.co.atom.xml")
    user.accounts.find_or_create_by!(platform_tag: "mastodon", label: "@testperson", credentials: {
      base_url: "https://mastodon.social",
      access_token: "SOME_TOKEN"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2024-10-26-13h47m04s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("mastodon_take") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "113935658428064993", crosspost.remote_id
    assert_equal "https://mastodon.social/@searls/113935658428064993", crosspost.url
    assert_equal "Look, all I want from political news—literally the only thing I’m asking for, and it isn’t much—is to tell me the literal future exactly as it will unfold so that my brain can go back to focusing on anything else.", crosspost.content

    # Post a Shot post
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/shots/2024-10-28-09h56m20s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("mastodon_shot") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "113935670111298635", crosspost.remote_id
    assert_equal "https://mastodon.social/@searls/113935670111298635", crosspost.url
    assert_equal "Orlando, I love you 🎶 https://justin.searls.co/shots/2024-10-28-09h56m20s/", crosspost.content

    # Post a Take with hyperlinks that have been truncated (regression test to make sure we look at the href not the link content)
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2025-01-22-15h46m11s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("mastodon_take_href") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "113991777044908687", crosspost.remote_id
    assert_equal "https://mastodon.social/@alharrington/113991777044908687", crosspost.url
    assert_equal "\"How hard could it possibly be to truncate a string while making sure it doesn't cut off any URLs or hashtags?\" he asked, ignorantly. https://gist.github.com/searls/9d8ee42929da99ae268477eb20818da6", crosspost.content
  end

  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/914ff8332cb956c77ac45a0dd182dc8a47f862a7/test/fixtures/files/media"
  BASE_URL = ENV.fetch("MASTODON_BASE_URL", "https://mastodon.example")

  def test_mastodon_posts_several_images
    crosspost = mastodon_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("mastodon_multi_image", except: [:body, :headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost, "https://example.com/social/stills/", media_count: 2
    assert_uploaded "image/jpeg", "An orange square"
    assert_uploaded "image/png", "A navy square"
  end

  def test_mastodon_posts_a_gif_from_its_platform_override
    crosspost = mastodon_crosspost_with_media("https://example.com/social/loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], mastodon_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("mastodon_gif", except: [:body, :headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost, "https://example.com/social/loop/", media_count: 1
    assert_uploaded "image/gif", "Orange, navy and paper squares in turn"
    assert_not_requested(:get, "#{MEDIA_BASE}/loop.mp4")
  end

  private

  def mastodon_crosspost_with_media(post_url, media, mastodon_media: media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "mastodon", label: "Mastodon", credentials: vcr_secrets({
      "base_url" => BASE_URL,
      "access_token" => ENV["MASTODON_ACCESS_TOKEN"]
    }))
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {mastodon: {media: mastodon_media, append_url: true, append_url_spacer: "\n\n"}}
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

  # The status carries the uploaded media, the entry's URL appended to the text, and the
  # crosspost's idempotency key
  def assert_published_with_media(crosspost, post_url, media_count:)
    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_nil crosspost.metadata["media_fallback"]
    assert_match %r{\A#{Regexp.escape(BASE_URL)}/@\w+/\d+\z}o, crosspost.url
    assert_requested(:post, "#{BASE_URL}/api/v1/statuses", headers: {"Idempotency-Key" => "posse-party-crosspost-#{crosspost.id}"}) { |request|
      body = JSON.parse(request.body)
      body["status"] == "PosseParty media test (deleted after recording)\n\n#{post_url}" && body["media_ids"].size == media_count
    }
  end

  def assert_uploaded(content_type, description)
    assert_requested(:post, "#{BASE_URL}/api/v2/media") { |request|
      request.body.include?("Content-Type: #{content_type}\r\n") && request.body.include?(%(name="description"\r\n\r\n#{description}))
    }
  end
end
