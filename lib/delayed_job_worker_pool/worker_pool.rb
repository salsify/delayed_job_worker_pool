# frozen_string_literal: true

require 'fcntl'
require 'socket'

module DelayedJobWorkerPool
  class WorkerPool

    SIGNALS = ['TERM', 'INT'].map(&:freeze).freeze
    DEFAULT_WORKER_COUNT = 1

    def initialize(options = {})
      @options = options
      @registry = Registry.new
      @pending_signals = []
      @pending_signal_read_pipe, @pending_signal_write_pipe = create_pipe(inheritable: false)
      @master_alive_read_pipe, @master_alive_write_pipe = create_pipe(inheritable: true)
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

      fork_workers

      monitor_workers

      exit
    ensure
      master_alive_write_pipe.close if master_alive_write_pipe
      master_alive_read_pipe.close if master_alive_read_pipe
    end

    private

    attr_reader :options, :registry, :master_alive_read_pipe, :master_alive_write_pipe,
                :pending_signals, :pending_signal_read_pipe, :pending_signal_write_pipe
    attr_accessor :shutting_down

    def install_signal_handlers
      SIGNALS.each do |signal|
        trap(signal) do
          pending_signals << signal
          pending_signal_write_pipe.write_nonblock('.')
        end
      end
    end

    def uninstall_signal_handlers
      SIGNALS.each do |signal|
        trap(signal, 'DEFAULT')
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

    def load_app
      DelayedJobWorkerPool::Application.load
    end

    def shutdown(signal)
      log("Shutting down master #{Process.pid} with signal #{signal}")
      self.shutting_down = true
      registry.worker_pids.each do |child_pid|
        group = registry.group(child_pid)
        log("Telling worker #{child_pid} from group #{group} to shutdown with signal #{signal}")
        Process.kill(signal, child_pid)
      end
    end

    def monitor_workers
      while has_workers?
        if has_pending_signal?
          shutdown(pending_signals.pop)
        elsif (wait_result = Process.wait2(-1, Process::WNOHANG))
          handle_dead_worker(wait_result.first, wait_result.last)
        else
          wait_for_signal(1)
        end
      end
    end

    def handle_dead_worker(worker_pid, status)
      return unless registry.include_worker?(worker_pid)

      log("Worker #{worker_pid} exited with status #{status.to_i}")

      group = registry.group(worker_pid)
      invoke_callback(:after_worker_shutdown, worker_info(worker_pid, group))

      registry.remove_worker(worker_pid)
      fork_worker(group) unless shutting_down
    end

    def has_workers?
      registry.has_workers?
    end

    def has_pending_signal?
      !pending_signals.empty?
    end

    def invoke_callback(callback_name, *args)
      options[callback_name].call(*args) if options[callback_name]
    end

    def fork_workers
      options.fetch(:worker_groups).each do |name, group|
        workers = group.workers || DEFAULT_WORKER_COUNT

        registry.add_group(name, group.dj_worker_options)

        workers.times { fork_worker(name) }
      end
    end

    def fork_worker(group)
      worker_pid = Kernel.fork { run_worker(group) }
      log("Started worker in group #{group}: #{worker_pid}")

      registry.add_worker(group, worker_pid)

      invoke_callback(:after_worker_boot, worker_info(worker_pid, group))
    end

    def run_worker(group)
      master_alive_write_pipe.close

      uninstall_signal_handlers

      Thread.new do
        IO.select([master_alive_read_pipe])
        log('Detected dead master. Shutting down worker.')
        exit(1)
      end

      load_app unless preload_app?

      invoke_callback(:on_worker_boot, worker_info(Process.pid, group))

      DelayedJobWorkerPool::Worker.run(worker_options(Process.pid, group))
    rescue StandardError => e
      log("Worker failed with error: #{e.message}\n#{e.backtrace.join("\n")}")
      exit(1)
    end

    def worker_info(worker_pid, group)
      DelayedJobWorkerPool::WorkerInfo.new(
        name: worker_name(worker_pid, group),
        process_id: worker_pid,
        worker_group: group
      )
    end

    def worker_name(worker_pid, group)
      "host:#{Socket.gethostname} pid:#{worker_pid} group:#{group}"
    end

    def preload_app?
      options.fetch(:preload_app, false)
    end

    def worker_options(worker_pid, group)
      registry.options(group).merge(name: worker_name(worker_pid, group))
    end

    def create_pipe(inheritable: true)
      read, write = IO.pipe
      unless inheritable
        make_file_descriptor_uninheritable(read)
        make_file_descriptor_uninheritable(write)
      end
      [read, write]
    end

    def make_file_descriptor_uninheritable(io)
      io.fcntl(Fcntl::F_SETFD)
    end

    def wait_for_signal(timeout)
      drain_pipe(pending_signal_read_pipe) if IO.select([pending_signal_read_pipe], [], [], timeout)
    end

    def drain_pipe(pipe)
      loop { pipe.read_nonblock(16) }
    rescue IO::WaitReadable
      # We've drained the pipe
    end

    def log(message)
      puts(message)
    end
  end
end
