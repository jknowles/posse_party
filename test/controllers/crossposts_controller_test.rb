require "test_helper"

class CrosspostsControllerTest < ActionDispatch::IntegrationTest
  def test_destroy_deletes_and_redirects
    user = users(:admin) # owns the admin_* fixtures
    login_as(user)

    crosspost = crossposts(:admin_bsky_crosspost)
    post = crosspost.post

    delete crosspost_path(crosspost)

    assert_redirected_to post_path(post)
    assert_equal "Crosspost deleted successfully.", flash[:notice]
    assert_nil Crosspost.find_by(id: crosspost.id)
  end

  def test_destroy_refuses_when_job_is_claimed
    user = users(:admin)
    login_as(user)

    crosspost = crossposts(:admin_bsky_crosspost)

    job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: PublishCrosspostJob.name,
      arguments: [].to_yaml,
      concurrency_key: "#{PublishCrosspostJob.name}/#{crosspost.id}"
    )
    process = SolidQueue::Process.create!(
      kind: "worker",
      last_heartbeat_at: Now.time,
      pid: 12345,
      name: "test-worker"
    )
    SolidQueue::ClaimedExecution.create!(job: job, process: process)

    delete crosspost_path(crosspost)

    assert_redirected_to crosspost_path(crosspost)
    assert_equal "Cannot delete crosspost while a job is in progress. Please wait and try again.", flash[:alert]
    assert_not_nil Crosspost.find_by(id: crosspost.id)
  end

  def test_mark_published_records_the_url
    login_as(users(:admin))
    crosspost = posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready")

    patch mark_published_crosspost_path(crosspost), params: {url: "https://x.com/searls/status/123"}

    assert_redirected_to crosspost_path(crosspost)
    assert_equal "Crosspost marked as published", flash[:notice]
    assert_equal "published", crosspost.reload.status
  end

  def test_mark_published_rejects_a_blank_url
    login_as(users(:admin))
    crosspost = posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready")

    patch mark_published_crosspost_path(crosspost), params: {url: ""}

    assert_equal "A URL is required to mark a crosspost as published", flash[:alert]
    assert_equal "ready", crosspost.reload.status
  end

  def test_show_offers_a_manual_compose_link_for_x
    login_as(users(:admin))

    get crosspost_path(posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready"))

    assert_select "a[href^='https://x.com/intent/tweet?text=']"
  end

  def test_show_offers_no_manual_compose_link_once_published
    login_as(users(:admin))
    crosspost = posts(:admin_post).crossposts.create!(
      account: accounts(:admin_x_account),
      status: "published",
      url: "https://x.com/searls/status/123"
    )

    get crosspost_path(crosspost)

    assert_select "a[href^='https://x.com/intent/tweet']", false
  end

  def test_show_offers_a_mark_published_form_for_x
    login_as(users(:admin))

    get crosspost_path(posts(:admin_post).crossposts.create!(account: accounts(:admin_x_account), status: "ready"))

    assert_select "form[action=?]", mark_published_crosspost_path(Crosspost.last)
  end

  def test_show_offers_no_manual_compose_link_for_platforms_without_one
    login_as(users(:admin))

    get crosspost_path(crossposts(:admin_bsky_crosspost))

    assert_select "a[href^='https://x.com/intent/tweet']", false
  end
end
