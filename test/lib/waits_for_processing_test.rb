require "test_helper"

class WaitsForProcessingTest < ActiveSupport::TestCase
  def setup
    @subject = WaitsForProcessing.new
  end

  def test_answers_true_once_the_block_does
    answers = [false, nil, true]

    ready = @subject.wait(timeout: 1, interval: 0) { answers.shift }

    assert_equal true, ready
    assert_empty answers
  end

  def test_answers_false_when_the_time_runs_out
    asked = 0

    ready = @subject.wait(timeout: 0.05, interval: 0.01) {
      asked += 1
      false
    }

    assert_equal false, ready
    assert_operator asked, :>, 1
  end

  def test_never_sleeps_past_the_deadline
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @subject.wait(timeout: 0.05, interval: 10) { false }

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end
end
