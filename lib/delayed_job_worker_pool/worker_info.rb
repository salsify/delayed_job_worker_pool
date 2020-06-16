module DelayedJobWorkerPool
  class WorkerInfo
    attr_reader :process_id, :name, :worker_group

    def initialize(attributes)
      @process_id = attributes.fetch(:process_id)
      @name = attributes.fetch(:name)
      @worker_group = attributes.fetch(:worker_group)
    end
  end
end
