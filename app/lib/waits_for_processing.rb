class WaitsForProcessing
  # Asks the block until it answers truthy or the time runs out, and says which happened. Time is
  # measured on the monotonic clock: a test can freeze Now, and a frozen clock never runs out.
  def wait(timeout: 60, interval: 3)
    deadline = clock + timeout
    loop do
      return true if yield

      remaining = deadline - clock
      return false unless remaining.positive?

      sleep([interval, remaining].min)
    end
  end

  private

  def clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
