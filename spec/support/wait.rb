# frozen_string_literal: true

module Wait
  extend self

  def for(condition_name, max_wait_time: 60, polling_interval: 0.001)
    wait_until = Time.now + max_wait_time
    loop do
      return if yield
      if Time.now > wait_until
        raise Timeout::Error.new("Condition not met: #{condition_name}")
      else
        sleep(polling_interval)
      end
    end
  end
end
