# frozen_string_literal: true

module DelayedJobWorkerPool
  class WorkerGroupOptions
    DJ_SETTINGS = [:queues, :min_priority, :max_priority, :sleep_delay, :read_ahead].freeze
    GROUP_SETTINGS = [:workers].freeze

    attr_accessor *DJ_SETTINGS, *GROUP_SETTINGS

    # @return an options hash for `Delayed::Worker`
    def dj_worker_options
      DJ_SETTINGS.each_with_object({}) do |setting, memo|
        memo[setting] = send(setting)
      end.compact
    end
  end
end
