require "test_helper"
require_relative "support/test_route_helpers"
require_relative "support/database_helpers"
require_relative "support/auth_mode_helpers"

Capybara.register_driver :my_playwright do |app|
  Capybara::Playwright::Driver.new(app,
    browser_type: ENV["PLAYWRIGHT_BROWSER"]&.to_sym || :chromium,
    headless: (false unless ENV["CI"] || ENV["PLAYWRIGHT_HEADLESS"]),
    # Smooth scrolling animates elements under Capybara's feet, producing "element is
    # not stable" timeouts and transiently non-visible flash messages.
    reducedMotion: "reduce")
end

Capybara.enable_aria_label = true

# The stock 2s is tight for a parallel suite doing real form posts and Turbo frame
# round trips; raising it removes timeout flake without weakening any assertion.
Capybara.default_max_wait_time = 8

Capybara.server = :puma, {Silent: true}

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include TestRouteHelpers
  include DatabaseHelpers
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include AuthModeHelpers

  if ENV["SERIAL"]
    parallelize(workers: 1)
  else
    parallelize(threshold: 0)
  end

  driven_by :my_playwright
  self.use_transactional_tests = true

  def login_as(user)
    set_session_var(:user_id, user.id)
  end

  def find_aria(*nested_labels, **kwargs)
    nested_labels.reduce(page) do |current_scope, label|
      current_scope.find("[aria-label='#{label}']", **kwargs)
    end
  end

  # Turbo marks a frame [busy] while its request is in flight. Waiting for every
  # frame to settle keeps a late swap from re-rendering an element mid-interaction
  # (and re-running the Stimulus connect() that resets its state).
  def wait_for_turbo_frames
    assert_no_selector "turbo-frame[busy]"
  end

  def click_aria(*nested_labels, retries: 3, **kwargs)
    retries.times do
      find_aria(*nested_labels, **kwargs).click
      return
    rescue => e
      raise e if retries == 0 || !e.message.include?("Element is not attached to the DOM")
      sleep 0.1
    end
  end
end
