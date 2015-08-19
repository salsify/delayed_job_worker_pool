module DelayedJobWorkerPool
  class WorkerPool
    def initialize(options = {})
      @options = options
      @worker_pids = []
      self.shutting_down = false
    end

    def run
      log("Starting master #{Process.pid}")

      install_signal_handlers

      if preload_app?
        load_app
        invoke_callback(:after_preload_app)
      end

      log_uninheritable_threads

      create_master_alive_pipe
      num_workers.times { fork_worker }

      monitor_workers

      exit
    ensure
      master_alive_write_pipe.close if master_alive_write_pipe
      master_alive_read_pipe.close if master_alive_read_pipe
    end

    private

    attr_reader :options, :worker_pids, :master_alive_read_pipe, :master_alive_write_pipe
    attr_accessor :shutting_down

    def install_signal_handlers
      trap('TERM') do
        shutdown('TERM')
      end

      trap('INT') do
        shutdown('INT')
      end
    end

    def log_uninheritable_threads
      Thread.list.each do |t|
        next if t == Thread.current
        if t.respond_to?(:backtrace)
          log("WARNING: Thread will not be inherited by workers: #{t.inspect} - #{t.backtrace ? t.backtrace.first : ''}")
        else
          log("WARNING: Thread will not be inherited by workers: #{t.inspect}")
        end
      end
    end

    def create_master_alive_pipe
      @master_alive_read_pipe, @master_alive_write_pipe = IO.pipe
    end

    def load_app
      DelayedJobWorkerPool::Application.load
    end

    def shutdown(signal)
      log("Shutting down master #{Process.pid} with signal #{signal}")
      self.shutting_down = true
      worker_pids.each do |child_pid|
        log("Telling worker #{child_pid} to shutdown with signal #{signal}")
        Process.kill(signal, child_pid)
      end
    end

    def monitor_workers
      until worker_pids.empty?
        worker_pid, status = Process.wait2

        next unless worker_pids.include?(worker_pid)

        log("Worker #{worker_pid} exited with status #{status.to_i}")
        worker_pids.delete(worker_pid)
        invoke_callback(:after_worker_shutdown, worker_pid)
        fork_worker unless shutting_down
      end
    end

    def invoke_callback(callback_name, *args)
      options[callback_name].call(*args) if options[callback_name]
    end

    def fork_worker
      worker_pid = Kernel.fork { run_worker }
      worker_pids << worker_pid
      log("Started worker #{worker_pid}")
      invoke_callback(:after_worker_boot, worker_pid)
    end

    def run_worker
      master_alive_write_pipe.close

      Thread.new do
        IO.select([master_alive_read_pipe])
        log('Detected dead master. Shutting down worker.')
        exit(1)
      end

      load_app unless preload_app?

      invoke_callback(:on_worker_boot)

      DelayedJobWorkerPool::Worker.run(worker_options)
    rescue => e
      log("Worker failed with error: #{e.message}\n#{e.backtrace.join("\n")}")
      exit(1)
    end

    def num_workers
      options.fetch(:workers, 1)
    end

    def preload_app?
      options.fetch(:preload_app, false)
    end

    def worker_options
      options.except(:workers, :preload_app, :before_worker_boot, :on_worker_boot, :after_worker_boot)
    end

    def log(message)
      puts(message)
    end
  end
end
