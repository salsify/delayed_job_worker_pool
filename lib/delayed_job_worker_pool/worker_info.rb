module DelayedJobWorkerPool
  class WorkerInfo
    attr_reader :process_id, :name

    def initialize(attributes)
      @process_id = attributes.fetch(:process_id)
      @name = attributes.fetch(:name)
    end

  end
end
