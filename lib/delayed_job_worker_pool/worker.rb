# frozen_string_literal: true

module DelayedJobWorkerPool
  module Worker
    extend self

    def run(options = {})
      dj_worker = Delayed::Worker.new(options)
      dj_worker.name = options[:name] if options.include?(:name)
      dj_worker.start
    end
  end
end
