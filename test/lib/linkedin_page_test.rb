require "test_helper"

# Recorded against a real Company Page; each post was deleted after recording
class LinkedinPageTest < ActiveSupport::TestCase
  include LinkedinMediaHelpers

  def test_linkedin_page_posts_a_link_card_with_its_thumbnail
    crosspost = linkedin_page_crosspost("https://example.com/social/page-card/", [], overrides: {
      attach_link: true, append_url: false, og_image: "#{MEDIA_BASE}/still.jpg"
    })

    perfect_vcr_match("linkedin_page_card") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "images"
    assert_requested(:post, "https://api.linkedin.com/rest/posts") { |request|
      JSON.parse(request.body, symbolize_names: true) in {
        author: ^(organization_urn(crosspost)),
        commentary: "PosseParty media test \\(deleted after recording\\)",
        content: {article: {source: "https://example.com/social/page-card/", thumbnail: /\Aurn:li:image:/}}
      }
    }
  end

  def test_linkedin_page_posts_one_image_with_its_alt_text
    crosspost = linkedin_page_crosspost("https://example.com/social/page-still/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"}
    ])

    perfect_vcr_match("linkedin_page_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "images"
    assert_linkedin_post(author: organization_urn(crosspost), post_url: "https://example.com/social/page-still/") { |content| content in {media: {id: /\Aurn:li:image:/, altText: "An orange square"}} }
  end

  def test_linkedin_page_posts_several_images_as_a_multi_image
    crosspost = linkedin_page_crosspost("https://example.com/social/page-stills/", [
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.jpg", "alt" => "An orange square", "mime" => "image/jpeg"},
      {"type" => "image", "url" => "#{MEDIA_BASE}/still.png", "alt" => "A navy square", "mime" => "image/png"}
    ])

    perfect_vcr_match("linkedin_page_multi_image") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "images", times: 2
    assert_linkedin_post(author: organization_urn(crosspost), post_url: "https://example.com/social/page-stills/") { |content|
      content in {multiImage: {images: [{id: /\Aurn:li:image:/, altText: "An orange square"}, {id: /\Aurn:li:image:/, altText: "A navy square"}]}}
    }
  end

  def test_linkedin_page_posts_a_gif_from_its_platform_override
    crosspost = linkedin_page_crosspost("https://example.com/social/page-loop/", [
      {"type" => "video", "url" => "#{MEDIA_BASE}/loop.mp4", "presentation" => "gif"}
    ], platform_media: [
      {"type" => "image", "url" => "#{MEDIA_BASE}/loop.gif", "alt" => "Orange, navy and paper squares in turn", "mime" => "image/gif"}
    ])

    perfect_vcr_match("linkedin_page_gif") do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "images"
    assert_linkedin_post(author: organization_urn(crosspost), post_url: "https://example.com/social/page-loop/") { |content| content in {media: {id: /\Aurn:li:image:/, altText: "Orange, navy and paper squares in turn"}} }
    assert_not_requested(:get, "#{MEDIA_BASE}/loop.mp4")
  end

  def test_linkedin_page_posts_a_silent_loop_as_a_video
    stub_fixture("loop.mp4", "video/mp4")
    crosspost = linkedin_page_crosspost("https://example.com/social/page-video-loop/", [
      {"type" => "video", "url" => "#{VIDEO_BASE}/loop.mp4", "alt" => "A test pattern, four seconds, silent", "mime" => "video/mp4", "presentation" => "gif"}
    ])

    # The part's body is the fixture, which the cassette does not keep
    perfect_vcr_match("linkedin_page_video_loop", except: [:body]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "videos"
    assert_linkedin_post(author: organization_urn(crosspost), post_url: "https://example.com/social/page-video-loop/") { |content| content in {media: {id: /\Aurn:li:video:/}} }
  end

  def test_linkedin_page_posts_a_clip_with_its_poster
    stub_fixture("clip.mp4", "video/mp4")
    stub_fixture("still.jpg", "image/jpeg")
    crosspost = linkedin_page_crosspost("https://example.com/social/page-video-clip/", [
      {"type" => "video", "url" => "#{VIDEO_BASE}/clip.mp4", "poster_url" => "#{VIDEO_BASE}/still.jpg", "alt" => "A test pattern with a tone", "mime" => "video/mp4"}
    ])

    perfect_vcr_match("linkedin_page_video_clip", except: [:body]) do
      PublishesCrosspost.new.publish(crosspost.id)
    end

    assert_published_with_media crosspost
    assert_owned_by_organization crosspost, "videos"
    assert_linkedin_post(author: organization_urn(crosspost), post_url: "https://example.com/social/page-video-clip/") { |content| content in {media: {id: /\Aurn:li:video:/}} }
    assert_requested(:put, /dms-uploads/, headers: {"media-type-family" => "STILLIMAGE"}) { |request| request.body.b == file_fixture("media/still.jpg").binread }
  end

  private

  def linkedin_page_crosspost(post_url, media, **)
    linkedin_crosspost_with_media(post_url, media, platform_tag: "linkedin_page", credentials: {
      "client_id" => nil,
      "client_secret" => nil,
      "access_token" => ENV["LINKEDIN_PAGE_ACCESS_TOKEN"],
      "organization_urn" => ENV["LINKEDIN_ORGANIZATION_URN"]
    }, **)
  end

  def organization_urn(crosspost)
    crosspost.account.credentials["organization_urn"]
  end

  # Every image or video the post uploads is owned by the organization, not the member
  def assert_owned_by_organization(crosspost, resource, times: 1)
    assert_requested(:post, "https://api.linkedin.com/rest/#{resource}?action=initializeUpload", times:) { |request|
      JSON.parse(request.body, symbolize_names: true) in {initializeUploadRequest: {owner: ^(organization_urn(crosspost))}}
    }
  end
end
