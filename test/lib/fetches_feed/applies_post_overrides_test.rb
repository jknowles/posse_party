require "test_helper"

class FetchesFeed
  class AppliesPostOverridesTest < ActiveSupport::TestCase
    setup do
      @subject = AppliesPostOverrides.new
    end

    def test_keeps_media_a_platform_override_lists
      attrs = @subject.apply({}, '{"platform_overrides":{"instagram":{"media":[{"type":"image","url":"https://example.com/a.jpg"}]}}}')

      assert_equal [{type: "image", url: "https://example.com/a.jpg"}], attrs[:platform_overrides][:instagram][:media]
    end

    def test_empties_override_media_that_is_not_a_list
      attrs = @subject.apply({}, '{"platform_overrides":{"instagram":{"media":"https://example.com/a.jpg"}}}')

      assert_equal [], attrs[:platform_overrides][:instagram][:media]
    end

    def test_leaves_an_override_without_media_alone
      attrs = @subject.apply({}, '{"platform_overrides":{"bsky":{"format_string":"{{title}}"}}}')

      assert_equal({format_string: "{{title}}"}, attrs[:platform_overrides][:bsky])
    end
  end
end
