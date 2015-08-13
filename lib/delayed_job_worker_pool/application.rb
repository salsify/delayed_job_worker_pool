module DelayedJobWorkerPool
  module Application
    extend self

    def load
      require(base_application_filename)
    rescue LoadError
      raise "Could not find Rails initialization file #{full_application_filename}. " \
            "Make sure delayed_job_worker_pool is run from the Rails root directory."
    end

    private

    def base_application_filename
      "#{Dir.pwd}/config/environment"
    end

    def full_application_filename
      "#{base_application_filename}.rb"
    end
  end
end
