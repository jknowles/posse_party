require "test_helper"

class PublishesCrosspostTest < ActiveSupport::TestCase
  def test_a_new_attempt_clears_the_media_fallback_an_earlier_attempt_recorded
    account = New.create(Account, user: users(:admin), platform_tag: "test", label: "@test", active: true)
    crosspost = Crosspost.create!(post: posts(:admin_post), account:, status: "wip", metadata: {
      "post" => "kept",
      "media_fallback" => {"reason" => "Could not download https://example.com/a.png: HTTP 503", "at" => "2026-10-06T10:00:00Z"}
    })

    PublishesCrosspost.new.publish(crosspost.id)

    assert_equal "published", crosspost.reload.status
    assert_equal({"post" => "kept"}, crosspost.metadata)
  end
end
