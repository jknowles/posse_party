require "test_helper"

class RecordsMediaFallbackTest < ActiveSupport::TestCase
  def test_records_the_reason_in_the_crosspost_metadata
    crosspost = crossposts(:admin_bsky_crosspost)
    crosspost.update!(metadata: {"post" => "kept"})
    Now.override!(Time.zone.parse("2026-10-06 10:00:00 UTC"), freeze: true)

    RecordsMediaFallback.new.record(crosspost, "LinkedIn takes JPEG, PNG and GIF, not image/webp")

    assert_equal({
      "post" => "kept",
      "media_fallback" => {"reason" => "LinkedIn takes JPEG, PNG and GIF, not image/webp", "at" => "2026-10-06T10:00:00Z"}
    }, crosspost.reload.metadata)
  end

  def test_logs_that_the_post_did_not_carry_all_its_media
    log = StringIO.new
    logger = ActiveSupport::Logger.new(log)
    Rails.logger.broadcast_to(logger)
    crosspost = crossposts(:admin_bsky_crosspost)

    RecordsMediaFallback.new.record(crosspost, "Mastodon takes at most 4 images; dropped 2")

    assert_includes log.string, "Crosspost #{crosspost.id} did not post all of its media: Mastodon takes at most 4 images; dropped 2"
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end
