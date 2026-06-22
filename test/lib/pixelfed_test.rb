require "test_helper"

class PixelfedTest < ActiveSupport::TestCase
  def test_syndication_uploads_media_then_posts_a_status
    user = New.create(User, email: "user@example.com")
    feed = fake_feed_from(user, "2025-06-18-justin.searls.co.atom.xml")
    user.accounts.find_or_create_by!(platform_tag: "pixelfed", label: "@testperson", credentials: {
      base_url: "https://pixelfed.social",
      access_token: "SOME_TOKEN"
    })

    FetchesFeed.new.fetch!(feed, cache: false)

    image_url = "https://justin.searls.co/shots/2025-06-15-09h26m00s-a30adcd.jpeg"
    stub_request(:get, image_url)
      .to_return(status: 200, headers: {"Content-Type" => "image/jpeg"}, body: "fake-image-bytes")
    media_stub = stub_request(:post, "https://pixelfed.social/api/v1/media")
      .to_return(status: 200, headers: {"Content-Type" => "application/json"}, body: {id: "111"}.to_json)
    status_stub = stub_request(:post, "https://pixelfed.social/api/v1/statuses")
      .to_return(status: 200, headers: {"Content-Type" => "application/json"},
        body: {id: "999", url: "https://pixelfed.social/p/searls/999"}.to_json)

    crosspost = Post.find_by(remote_id: "https://justin.searls.co/shots/2025-06-15-14h42m44s/").crossposts.first
    crosspost.update!(status: "wip")

    PublishesCrosspost.new.publish(crosspost.id)

    assert_empty crosspost.reload.failures
    assert_equal "published", crosspost.status
    assert_equal 1, crosspost.attempts
    assert_equal "999", crosspost.remote_id
    assert_equal "https://pixelfed.social/p/searls/999", crosspost.url
    assert_equal <<~MSG.strip, crosspost.content
      Nearly all Japan's overtourism woes could be solved overnight if the nation simply outlawed roller bags.

      See the full post at:
      https://justin.searls.co/shots/2025-06-15-14h42m44s/
    MSG
    assert_requested media_stub
    assert_requested status_stub
    assert_requested(:post, "https://pixelfed.social/api/v1/statuses") do |request|
      JSON.parse(request.body)["media_ids"] == ["111"]
    end
  end

  def test_skips_posts_without_media
    user = New.create(User, email: "nomedia@example.com")
    feed_url = "https://example.com/feed.xml"
    post_url = "https://example.com/takes/2025-06-20"
    stub_request(:get, feed_url).to_return(status: 200, body: <<~XML)
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
        <title>Test Feed</title>
        <id>#{feed_url}</id>
        <updated>2025-06-20T00:00:00Z</updated>
        <entry>
          <title>A text-only take</title>
          <id>#{post_url}</id>
          <published>2025-06-20T00:00:00Z</published>
          <updated>2025-06-20T00:00:00Z</updated>
          <link rel="alternate" href="#{post_url}"/>
          <posse:post><![CDATA[{"syndicate":true,"media":[],"content":"<p>Just words, no picture.</p>"}]]></posse:post>
        </entry>
      </feed>
    XML
    user.accounts.find_or_create_by!(platform_tag: "pixelfed", label: "@testperson", credentials: {
      base_url: "https://pixelfed.social",
      access_token: "SOME_TOKEN"
    })
    feed = user.feeds.create!(url: feed_url, label: "example - test")

    FetchesFeed.new.fetch!(feed, cache: false)

    crosspost = Post.find_by(remote_id: post_url).crossposts.first
    crosspost.update!(status: "wip")

    PublishesCrosspost.new.publish(crosspost.id)

    assert_equal "skipped", crosspost.reload.status
    assert_not_requested :post, "https://pixelfed.social/api/v1/statuses"
  end

  def test_skips_posts_whose_only_media_is_video
    user = New.create(User, email: "videoonly@example.com")
    feed_url = "https://example.com/feed.xml"
    post_url = "https://example.com/clips/2025-06-20"
    stub_request(:get, feed_url).to_return(status: 200, body: <<~XML)
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom" xmlns:posse="https://posseparty.com/2024/Feed">
        <title>Test Feed</title>
        <id>#{feed_url}</id>
        <updated>2025-06-20T00:00:00Z</updated>
        <entry>
          <title>A video-only clip</title>
          <id>#{post_url}</id>
          <published>2025-06-20T00:00:00Z</published>
          <updated>2025-06-20T00:00:00Z</updated>
          <link rel="alternate" href="#{post_url}"/>
          <posse:post><![CDATA[{"syndicate":true,"media":[{"type":"video","url":"https://example.com/clip.mp4"}],"content":"<p>A moving picture.</p>"}]]></posse:post>
        </entry>
      </feed>
    XML
    user.accounts.find_or_create_by!(platform_tag: "pixelfed", label: "@testperson", credentials: {
      base_url: "https://pixelfed.social",
      access_token: "SOME_TOKEN"
    })
    feed = user.feeds.create!(url: feed_url, label: "example - test")

    FetchesFeed.new.fetch!(feed, cache: false)

    crosspost = Post.find_by(remote_id: post_url).crossposts.first
    crosspost.update!(status: "wip")

    PublishesCrosspost.new.publish(crosspost.id)

    assert_equal "skipped", crosspost.reload.status
    assert_not_requested :post, "https://pixelfed.social/api/v1/media"
    assert_not_requested :post, "https://pixelfed.social/api/v1/statuses"
  end
end
