module DelayedJobWorkerPool
  module Worker
    extend self
    
    def run(options = {})
      dj_worker = Delayed::Worker.new(options)
      dj_worker.start
    end
  end
end
