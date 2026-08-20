require "test_helper"

class CrosspostsHelperTest < ActiveSupport::TestCase
  include CrosspostsHelper

  def test_shows_the_composed_content
    text = crosspost_preview_text(Result.success("Hello, world"))

    assert_equal "Hello, world", text
  end

  def test_explains_when_the_crosspost_would_be_skipped
    text = crosspost_preview_text(Result.success(nil))

    assert_equal "[Would be skipped - syndication disabled]", text
  end

  def test_reports_a_composition_failure_instead_of_postable_content
    error = RuntimeError.new("Content is too long")
    error.set_backtrace(["line one", "line two"])

    text = crosspost_preview_text(Result.failure(error))

    assert_equal "[Error generating preview: Content is too long]\n\nline one\nline two", text
  end
end
