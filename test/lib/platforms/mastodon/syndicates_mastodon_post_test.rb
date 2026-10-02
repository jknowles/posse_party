require "test_helper"

class Platforms::Mastodon::SyndicatesMastodonPostTest < ActiveSupport::TestCase
  STATUSES_URL = "https://mastodon.example/api/v1/statuses"

  def setup
    @uploads_mastodon_media = Mocktail.of_next(Platforms::Mastodon::UploadsMastodonMedia)
    @subject = Platforms::Mastodon::SyndicatesMastodonPost.new
    account = New.create(Account, user: users(:admin), platform_tag: "mastodon", label: "@test", active: true,
      credentials: {"base_url" => "https://mastodon.example", "access_token" => "token"})
    @crosspost = Crosspost.create!(post: posts(:admin_post), account:, status: "wip")
    @config = CrosspostConfig.new(media: [{"type" => "image", "url" => "https://example.com/media/still.png"}])
  end

  def test_posts_the_status_with_its_media_and_an_idempotency_key
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { media(["1", "2"], ready: true) }
    status = stub_status({status: "A map", media_ids: ["1", "2"]}, id: "900")

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_requested status
    assert_equal "published", @crosspost.reload.status
    assert_equal "900", @crosspost.remote_id
    assert_equal "https://mastodon.example/@test/900", @crosspost.url
    assert_equal "A map", @crosspost.content
    assert_requested(:post, STATUSES_URL, headers: {"Idempotency-Key" => @crosspost.metadata["mastodon_idempotency_key"]})
  end

  def test_without_media_posts_the_text_alone
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }
    status = stub_status({status: "A map"}, id: "901")

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_requested status
  end

  def test_media_still_processing_is_kept_to_post_later
    @crosspost.update!(metadata: {"post" => "kept"})
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { media(["1"], ready: false) }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert result.needs_to_finish?
    assert_equal "wip", @crosspost.reload.status
    assert_equal({"post" => "kept", "mastodon_media" => {"ids" => ["1"], "status" => "A map"}}, @crosspost.metadata)
    assert_not_requested :post, STATUSES_URL
  end

  def test_finishing_posts_the_kept_status_once_its_media_is_ready
    @crosspost.update!(metadata: {"mastodon_media" => {"ids" => ["1"], "status" => "A map"}})
    stubs { @uploads_mastodon_media.finish(@crosspost, ["1"]) }.with { media(["1"], ready: true) }
    status = stub_status({status: "A map", media_ids: ["1"]}, id: "902")

    result = @subject.finish!(@crosspost)

    assert result.success?
    assert_requested status
    assert_equal "published", @crosspost.reload.status
  end

  def test_finishing_asks_again_while_the_media_is_processing
    @crosspost.update!(metadata: {"mastodon_media" => {"ids" => ["1"], "status" => "A map"}})
    stubs { @uploads_mastodon_media.finish(@crosspost, ["1"]) }.with { media(["1"], ready: false) }

    result = @subject.finish!(@crosspost)

    assert result.needs_to_finish?
    assert_not_requested :post, STATUSES_URL
  end

  def test_finishing_with_nothing_kept_fails
    result = @subject.finish!(@crosspost)

    assert_not result.success?
    assert_equal "No Mastodon media is waiting to be posted", result.message
  end

  def test_a_failure_does_not_repeat_the_access_token
    @crosspost.account.update!(credentials: {"base_url" => "https://mastodon.example", "access_token" => "a warning\nSECRET-TOKEN-123"})
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert_not result.success?
    assert_includes result.error.message, "Bearer [FILTERED]"
    assert_not_includes result.error.message, "SECRET-TOKEN-123"
  end

  def test_a_retry_sends_the_idempotency_key_its_publish_already_kept
    @crosspost.update!(metadata: {"mastodon_idempotency_key" => "posse-party-crosspost-1-kept"})
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }
    status = stub_status({status: "A map"}, id: "903", key: "posse-party-crosspost-1-kept")

    result = @subject.syndicate!(@crosspost, @config, "A map")

    assert result.success?
    assert_requested status
  end

  def test_a_new_publish_cycle_gets_a_new_idempotency_key
    stubs { @uploads_mastodon_media.upload(@crosspost, @config) }.with { Platforms::Mastodon::UploadsMastodonMedia::NONE }
    stub_status({status: "A map"}, id: "904")
    @subject.syndicate!(@crosspost, @config, "A map")
    first_key = @crosspost.reload.metadata["mastodon_idempotency_key"]
    # A manual re-publish clears the metadata, as ManuallyPublishesCrosspost does
    @crosspost.update!(metadata: {})

    @subject.syndicate!(@crosspost, @config, "A map")

    assert_match(/\Aposse-party-crosspost-#{@crosspost.id}-\h{8}-/, first_key)
    assert_not_equal first_key, @crosspost.reload.metadata["mastodon_idempotency_key"]
  end

  private

  def media(ids, ready:)
    Platforms::Mastodon::UploadsMastodonMedia::Media.new(ids:, ready?: ready)
  end

  def stub_status(body, id:, key: /\Aposse-party-crosspost-#{@crosspost.id}-\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    stub_request(:post, STATUSES_URL)
      .with(body: body.to_json, headers: {"Authorization" => "Bearer token", "Idempotency-Key" => key})
      .to_return(status: 200, body: {id:, url: "https://mastodon.example/@test/#{id}"}.to_json, headers: {"Content-Type" => "application/json"})
  end
end
