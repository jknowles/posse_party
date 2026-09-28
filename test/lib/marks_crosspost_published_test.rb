require "test_helper"

class MarksCrosspostPublishedTest < ActiveSupport::TestCase
  def setup
    @subject = MarksCrosspostPublished.new
    @crosspost = posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready")
  end

  def teardown
    Now.reset!
  end

  def test_records_the_url_and_marks_it_published
    outcome = @subject.mark(@crosspost, "https://x.com/searls/status/123")

    assert outcome.success?, outcome.message
    assert_equal "published", @crosspost.reload.status
    assert_equal "https://x.com/searls/status/123", @crosspost.url
  end

  def test_stamps_published_at
    Now.override!(Time.utc(2026, 8, 20, 1, 31), freeze: true)

    @subject.mark(@crosspost, "https://x.com/searls/status/123")

    assert_equal Time.utc(2026, 8, 20, 1, 31), @crosspost.reload.published_at
  end

  def test_refuses_a_blank_url
    outcome = @subject.mark(@crosspost, "")

    assert outcome.failure?
    assert_equal "A URL is required to mark a crosspost as published", outcome.message
    assert_equal "ready", @crosspost.reload.status
  end

  def test_refuses_a_url_that_isnt_http
    outcome = @subject.mark(@crosspost, "javascript:alert(1)")

    assert outcome.failure?
    assert_equal "\"javascript:alert(1)\" is not a valid http(s) URL", outcome.message
    assert_equal "ready", @crosspost.reload.status
  end
end
