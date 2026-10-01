require "test_helper"

class BskyTest < ActiveSupport::TestCase
  def test_bsky_syndication
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-01-28-justin.searls.co.atom.xml")
    user.accounts.find_or_create_by!(platform_tag: "bsky", label: "Test Account", credentials: {
      email: "user@example.com",
      password: "password"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    # Post a take to bsky
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2024-10-29-09h22m34s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("bsky_take", time: "2025-01-29T03:03:55.226Z", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "at://did:plc:vvwq23uzqcsoekea65qzdddk/app.bsky.feed.post/3lgtybpyq7l23", crosspost.remote_id
    assert_equal "https://bsky.app/profile/alharrington.bsky.social/post/3lgtybpyq7l23", crosspost.url
    assert_equal "Three quick takes on ChatGPT integration in iOS 18.2:\n\n1. You can disable Siri prompting you for permission to query ChatGPT\n2. When using ChatGPT via Siri, you can type a follow-up and it’ll hold context and respond\n3. If you want to bypass vanilla Siri actions, you may need to preface... continued", crosspost.content

    # Post a Shot post
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/shots/2024-10-28-09h56m20s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("bsky_shot", time: "2025-01-29T14:25:02.263Z", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "at://did:plc:vvwq23uzqcsoekea65qzdddk/app.bsky.feed.post/3lgv6do363r2n", crosspost.remote_id
    assert_equal "https://bsky.app/profile/alharrington.bsky.social/post/3lgv6do363r2n", crosspost.url
    assert_equal "Orlando, I love you 🎶", crosspost.content
  end

  def test_bsky_link_fuckup
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-03-12-justin.searls.co.atom.xml")
    user.accounts.find_or_create_by!(platform_tag: "bsky", label: "Test Account", credentials: {
      email: "user@example.com",
      password: "password"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    # Post the offending take to bsky
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2025-03-08-16h39m24s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("bsky_cut_off_bug", time: "2025-03-12T22:02:45.990Z", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "at://did:plc:vvwq23uzqcsoekea65qzdddk/app.bsky.feed.post/3lk7litc2yu2y", crosspost.remote_id
    assert_equal "https://bsky.app/profile/alharrington.bsky.social/post/3lk7litc2yu2y", crosspost.url
    assert_equal "Two words: POSSE Party usher.dev/…", crosspost.content
  end

  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/914ff8332cb956c77ac45a0dd182dc8a47f862a7/test/fixtures/files/media"

  def test_bsky_posts_several_images_in_place_of_the_card
    crosspost = bsky_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg", "width" => 240, "height" => 240},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("bsky_multi_image", time: "2026-10-01T14:00:00.000Z", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    crosspost.reload
    assert_empty crosspost.failures
    assert_equal "published", crosspost.status
    assert_nil crosspost.metadata["media_fallback"]
    assert_match %r{\Aat://did:plc:[a-z0-9]+/app\.bsky\.feed\.post/[a-z0-9]+\z}, crosspost.remote_id
    assert_equal "PosseParty media test (deleted after recording)\n\n🔗", crosspost.content
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.uploadBlob", headers: {"Content-Type" => "image/jpeg"})
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.uploadBlob", headers: {"Content-Type" => "image/png"})
    assert_requested(:post, "#{Platforms::Bsky::SyndicatesBskyPost::PDS_URL}/xrpc/com.atproto.repo.createRecord") { |request|
      JSON.parse(request.body, symbolize_names: true)[:record] in {
        text: "PosseParty media test (deleted after recording)\n\n🔗",
        facets: [{features: [{uri: "https://example.com/social/stills/"}]}],
        embed: {"$type": "app.bsky.embed.images", images: [
          {alt: "An orange square", image: {mimeType: "image/jpeg"}, aspectRatio: {width: 240, height: 240}},
          {alt: "A navy square", image: {mimeType: "image/png"}, aspectRatio: {width: 240, height: 240}}
        ]}
      }
    }
  end

  private

  # attach_link stays at Bluesky's default, true, so the recording shows the card's link appended
  def bsky_crosspost_with_media(post_url, media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "bsky", label: "Bluesky", credentials: vcr_secrets({
      "email" => ENV["BSKY_EMAIL"],
      "password" => ENV["BSKY_PASSWORD"]
    }))
    filter_bsky_session_tokens
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {bsky: {append_url_spacer: "\n\n"}}
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

  # Bluesky issues its session tokens in createSession's response, so no environment variable
  # names them in advance. Later requests carry the access token as a Bearer header. The filters
  # touch only Bluesky's /xrpc/ calls, so they cannot rewrite another platform's recording.
  def filter_bsky_session_tokens
    VCR.configure do |config|
      config.filter_sensitive_data("ACCESS_JWT_PLACEHOLDER") { |interaction|
        if interaction.request.uri.include?("/xrpc/")
          interaction.response.body.to_s.b[/"accessJwt":"([^"]+)"/, 1] || interaction.request.headers["Authorization"]&.first&.delete_prefix("Bearer ")
        end
      }
      config.filter_sensitive_data("REFRESH_JWT_PLACEHOLDER") { |interaction|
        interaction.response.body.to_s.b[/"refreshJwt":"([^"]+)"/, 1] if interaction.request.uri.include?("/xrpc/")
      }
    end
  end
end
