require "test_helper"

class LinkedinTest < ActiveSupport::TestCase
  def test_linkedin_syndication
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-06-18-justin.searls.co.atom.xml")
    user.accounts.find_or_create_by!(platform_tag: "linkedin", label: "Test Page", credentials: {
      client_id: "someclientid",
      client_secret: "someclientsecret",
      access_token: "sometoken",
      person_urn: "urn:li:person:someperson"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2025-06-14-09h51m32s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("linkedin_take", except: [:headers]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "urn:li:share:7341301993115684864", crosspost.remote_id
    assert_equal "https://www.linkedin.com/feed/update/urn:li:share:7341301993115684864/", crosspost.url
    assert_equal "Been a fun couple of weeks touring more remote parts of Japan, and I'm happy to report I've now stayed at least one night in 46 of Japan's 47 prefectures. I'm saving the last—Hokkaido—for next year. RubyKaigiかな", crosspost.content
  end

  def test_linkedin_parentheses_escaping
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-07-08-justin.searls.co.atom.xml")

    # Using fake credentials for committed version
    user.accounts.find_or_create_by!(platform_tag: "linkedin", label: "Test Account", credentials: {
      client_id: "fakeclientid",
      expires_at: "2099-09-01T12:50:18Z",
      person_urn: "urn:li:person:fakepersonurn",
      access_token: "fakeaccesstoken",
      client_secret: "fakeclientsecret"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    # Get the post with parentheses in content
    crosspost = Post.find_by(remote_id: "https://justin.searls.co/takes/2025-07-06-17h23m32s/").crossposts.first
    crosspost.update!(status: "wip")

    perfect_vcr_match("linkedin_parentheses_fix") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    # Assertions based on the observed results
    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "urn:li:share:7348349577130860544", crosspost.remote_id
    assert_equal "https://www.linkedin.com/feed/update/urn:li:share:7348349577130860544/", crosspost.url

    # The key assertion: verify the content with parentheses was saved correctly
    assert_equal "Anybody else have a recent MacBook Pro (M4 Pro in my case) for which the keyboard suddenly became really squeaky? Every time I hit the space bar, it's like nails on a chalkboard.", crosspost.content
  end

  MEDIA_BASE = "https://raw.githubusercontent.com/jknowles/posse_party/feat/media-foundation/test/fixtures/files/media"

  def test_linkedin_posts_one_image_with_its_alt_text
    crosspost = linkedin_crosspost_with_media("https://example.com/social/still/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"}
    ])

    perfect_vcr_match("linkedin_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  def test_linkedin_posts_several_images_as_a_multi_image
    crosspost = linkedin_crosspost_with_media("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("linkedin_multi_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  def test_linkedin_posts_a_gif_from_its_platform_override
    crosspost = linkedin_crosspost_with_media("https://example.com/social/loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], linkedin_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("linkedin_gif") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
  end

  private

  def linkedin_crosspost_with_media(post_url, media, linkedin_media: media)
    user = New.create(User, email: "user@example.com")
    user.accounts.create!(platform_tag: "linkedin", label: "LinkedIn", credentials: vcr_secrets({
      "client_id" => nil,
      "client_secret" => nil,
      "access_token" => ENV["LINKEDIN_ACCESS_TOKEN"],
      "person_urn" => ENV["LINKEDIN_PERSON_URN"]
    }))
    posse = {
      syndicate: true,
      format_string: "{{content}}",
      content: "PosseParty media test (deleted after recording)",
      media:,
      platform_overrides: {linkedin: {media: linkedin_media, append_url: true, append_url_spacer: "\n\n", attach_link: false}}
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
end
