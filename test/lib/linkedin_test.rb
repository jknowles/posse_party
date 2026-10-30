require "test_helper"

class LinkedinTest < ActiveSupport::TestCase
  include LinkedinMediaHelpers

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

  def test_linkedin_posts_one_image_with_its_alt_text
    crosspost = linkedin_crosspost("https://example.com/social/still/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"}
    ])

    perfect_vcr_match("linkedin_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_linkedin_post(author: crosspost.account.credentials["person_urn"], post_url: "https://example.com/social/still/") { |content| content in {media: {id: /\Aurn:li:image:/, altText: "An orange square"}} }
    assert_requested(:put, /dms-uploads/, headers: {"Content-Type" => "image/jpeg"})
  end

  def test_linkedin_posts_several_images_as_a_multi_image
    crosspost = linkedin_crosspost("https://example.com/social/stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("linkedin_multi_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_linkedin_post(author: crosspost.account.credentials["person_urn"], post_url: "https://example.com/social/stills/") { |content|
      content in {multiImage: {images: [{id: /\Aurn:li:image:/, altText: "An orange square"}, {id: /\Aurn:li:image:/, altText: "A navy square"}]}}
    }
    assert_requested(:put, /dms-uploads/, headers: {"Content-Type" => "image/jpeg"})
    assert_requested(:put, /dms-uploads/, headers: {"Content-Type" => "image/png"})
  end

  def test_linkedin_posts_a_gif_from_its_platform_override
    crosspost = linkedin_crosspost("https://example.com/social/loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], platform_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("linkedin_gif") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_linkedin_post(author: crosspost.account.credentials["person_urn"], post_url: "https://example.com/social/loop/") { |content| content in {media: {id: /\Aurn:li:image:/, altText: "Orange, navy and paper squares in turn"}} }
    assert_requested(:put, /dms-uploads/, headers: {"Content-Type" => "image/gif"})
    assert_not_requested(:get, "#{MEDIA_BASE}/loop.mp4")
  end

  def test_linkedin_posts_a_silent_loop_as_a_video
    stub_fixture("loop.mp4", "video/mp4")
    crosspost = linkedin_crosspost("https://example.com/social/video-loop/", [
      {"type" => "video", "url" => "#{VIDEO_BASE}/loop.mp4", "alt" => "A test pattern, four seconds, silent", "mime" => "video/mp4", "presentation" => "gif"}
    ])

    # The part's body is the fixture, which the cassette does not keep; WebMock checks it below
    perfect_vcr_match("linkedin_video_loop", except: [:body]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_linkedin_post(author: crosspost.account.credentials["person_urn"], post_url: "https://example.com/social/video-loop/") { |content| content in {media: {id: /\Aurn:li:video:/}} }
    assert_requested(:post, "https://api.linkedin.com/rest/videos?action=initializeUpload") { |request|
      JSON.parse(request.body, symbolize_names: true) in {initializeUploadRequest: {fileSizeBytes: ^(file_fixture("media/loop.mp4").size), uploadThumbnail: false}}
    }
    assert_requested(:put, /dms-uploads/) { |request| request.body.b == file_fixture("media/loop.mp4").binread }
    assert_requested(:post, "https://api.linkedin.com/rest/videos?action=finalizeUpload") { |request|
      JSON.parse(request.body, symbolize_names: true) in {finalizeUploadRequest: {video: /\Aurn:li:video:/, uploadedPartIds: [_, *]}}
    }
  end

  def test_linkedin_posts_a_clip_with_its_poster
    stub_fixture("clip.mp4", "video/mp4")
    stub_fixture("still.jpg", "image/jpeg")
    crosspost = linkedin_crosspost("https://example.com/social/video-clip/", [
      {"type" => "video", "url" => "#{VIDEO_BASE}/clip.mp4", "poster_url" => "#{VIDEO_BASE}/still.jpg", "alt" => "A test pattern with a tone", "mime" => "video/mp4"}
    ])

    perfect_vcr_match("linkedin_video_clip", except: [:body]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_linkedin_post(author: crosspost.account.credentials["person_urn"], post_url: "https://example.com/social/video-clip/") { |content| content in {media: {id: /\Aurn:li:video:/}} }
    assert_requested(:post, "https://api.linkedin.com/rest/videos?action=initializeUpload") { |request|
      JSON.parse(request.body, symbolize_names: true) in {initializeUploadRequest: {fileSizeBytes: ^(file_fixture("media/clip.mp4").size), uploadThumbnail: true}}
    }
    assert_requested(:put, /dms-uploads/, headers: {"media-type-family" => "STILLIMAGE"}) { |request| request.body.b == file_fixture("media/still.jpg").binread }
    assert_requested(:post, "https://api.linkedin.com/rest/videos?action=finalizeUpload") { |request|
      JSON.parse(request.body, symbolize_names: true) in {finalizeUploadRequest: {video: /\Aurn:li:video:/, uploadedPartIds: [_, *]}}
    }
  end

  private

  def linkedin_crosspost(post_url, media, **)
    linkedin_crosspost_with_media(post_url, media, platform_tag: "linkedin", credentials: {
      "client_id" => nil,
      "client_secret" => nil,
      "access_token" => ENV["LINKEDIN_ACCESS_TOKEN"],
      "person_urn" => ENV["LINKEDIN_PERSON_URN"]
    }, **)
  end
end
