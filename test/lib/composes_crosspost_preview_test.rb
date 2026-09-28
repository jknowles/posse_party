require "test_helper"

class ComposesCrosspostPreviewTest < ActiveSupport::TestCase
  def setup
    @subject = ComposesCrosspostPreview.new
    @crosspost = posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready")
  end

  def test_composes_the_content_that_would_be_posted
    result = @subject.compose(@crosspost)

    assert result.success?
    assert_equal "Admin's First Post https://admin.example.com/posts/1", result.data
  end

  def test_returns_no_content_when_syndication_is_disabled
    @crosspost.post.update!(syndicate: false)

    result = @subject.compose(@crosspost)

    assert result.success?
    assert_nil result.data
  end

  def test_reports_failure_when_content_cannot_be_composed
    @crosspost.post.update!(title: "a" * 300, truncate: false, url: "https://admin.example.com/posts/1")

    result = @subject.compose(@crosspost)

    assert result.failure?
    assert_equal "Content is too long to post without truncation", result.error.message
  end
end
