require "test_helper"

class Platforms::LinkedinTest < ActiveSupport::TestCase
  def setup
    @syndicates_linkedin_post = Mocktail.of_next(Platforms::Linkedin::SyndicatesLinkedinPost)
    @subject = Platforms::Linkedin.new
    @crosspost = crossposts(:admin_bsky_crosspost)
  end

  def test_finishes_a_post_left_waiting_on_a_video
    stubs { @syndicates_linkedin_post.finish!(@crosspost) }.with { PublishesCrosspost::Result.new(success?: true) }

    assert @subject.finishable?
    assert @subject.finish!(@crosspost).success?
  end
end
