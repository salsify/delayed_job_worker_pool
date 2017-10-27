require 'spec_helper'
require 'open3'
require 'active_record'
require 'active_support/all'
require 'delayed_job_active_record'
require 'socket'
require_relative 'dummy/app/jobs/touch_file_job'

describe DelayedJobWorkerPool do
  let(:config_file) { config_file_path('preload_app.rb') }

  before(:all) do
    FileUtils.makedirs(log_dir)
    setup_test_app_database
  end

  before do |example|
    FileUtils.remove_dir(jobs_dir, true)
    FileUtils.makedirs(jobs_dir)
    start_worker_pool(example, config_file)
  end

  after do
    shutdown_worker_pool
    FileUtils.remove_dir(jobs_dir, true)
  end

  shared_examples 'runs jobs on active queues' do
    specify do
      inactive_job_file = "#{jobs_dir}/inactive.txt"
      queue_create_file_job(inactive_job_file, queue: 'inactive')

      active_job_file = "#{jobs_dir}/active.txt"
      queue_create_file_job(active_job_file, queue: 'active')

      Wait.for('job completed') do
        File.exists?(active_job_file)
      end

      expect(File.exists?(inactive_job_file)).to be_falsey
    end
  end

  it_behaves_like 'runs jobs on active queues'

  it 'invokes after_preload_app, on_worker_boot, and after_worker_boot callbacks' do
    worker_pids = wait_for_children_booted
    expect(worker_pids.size).to eq 1

    wait_for_num_log_lines(master_callback_log, 1 + worker_pids.size)
    worker_pid = worker_pids.first
    expect(parse_callback_log(master_callback_log)).to eq [
        { callback: 'after_preload_app', pid: master_pid },
        {
            callback: 'after_worker_boot',
            pid: master_pid,
            worker_pid: worker_pid,
            worker_name: expected_worker_name(worker_pid)
        }
    ]

    wait_for_num_log_lines(worker_callback_log, 1)
    expect(parse_callback_log(worker_callback_log)).to eq [
        {
            callback: 'on_worker_boot',
            pid: worker_pid,
            worker_pid: worker_pid,
            worker_name: expected_worker_name(worker_pid)
        }
    ]
  end

  context 'when the app is not preloaded' do
    let(:config_file) { config_file_path('postload_app.rb') }

    it_behaves_like 'runs jobs on active queues'
  end

  context 'when children fail' do
    before do
      # Wait until all of the children have started
      worker_pids = wait_for_children_booted
      wait_for_num_log_lines(master_callback_log, 1 + worker_pids.size)

      # Kill the initially booted workers so the master will restart them
      worker_pids.each do |child_worker_pid|
        kill_process(child_worker_pid, 'KILL')
        wait_for_process_terminated(child_worker_pid)
      end

      @killed_worker_pids = worker_pids
    end

    it_behaves_like 'runs jobs on active queues'

    it 'invokes after_worker_shutdown callbacks' do
      wait_for_children_booted
      wait_for_num_log_lines(master_callback_log, 1 + 3 * @killed_worker_pids.size)

      callback_messages = parse_callback_log(master_callback_log)
      @killed_worker_pids.each do |killed_worker_pid|
        expect(callback_messages).to include({
            callback: 'after_worker_shutdown',
            pid: master_pid,
            worker_pid: killed_worker_pid,
            worker_name: expected_worker_name(killed_worker_pid)
        })
      end
    end
  end

  it 'exits workers if the master process dies' do
    worker_pids = wait_for_children_booted

    kill_process(master_pid, 'KILL')

    worker_pids.each do |worker_pid|
      Wait.for('child terminated') do
        process_alive?(worker_pid)
      end
    end
  end

  def start_worker_pool(example, config_file, num_workers: 1, queues: ['active'])
    env = worker_pool_env(num_workers: num_workers, queues: queues)
    stdin, @master_stdout_err, @master_thread = Open3.popen2e(env, 'delayed_job_worker_pool', config_file, chdir: test_app_root)
    stdin.close
    @master_log_thread = Thread.new do
      log_worker_pool_output(example)
    end
  end

  def shutdown_worker_pool
    if process_alive?(master_pid)
      kill_process(master_pid, 'TERM')
      Process.wait(master_pid) rescue Errno::ECHILD
    end

    @master_stdout_err.close if @master_stdout_err

    if @master_log_thread && !@master_log_thread.join(2)
      puts 'WARNING: Failed to gracefully join master_log_thread'
      @master_log_thread.raise(ThreadShutdownException.new)
      @master_log_thread.join
    end
  end

  def master_pid
    @master_thread.pid
  end

  def wait_for_children_booted
    pids = []
    Wait.for('children started') do
      pids = child_worker_pids
      pids.present?
    end
    pids
  end

  def wait_for_num_log_lines(log, num_lines)
    log_contents = []
    Wait.for("#{log} contains #{num_lines} lines") do
      if File.exists?(log)
        log_contents = IO.readlines(log)
        log_contents.size == num_lines
      else
        false
      end
    end
  rescue Timeout::Error => e
    raise Timeout::Error.new("#{e.message}. Log contents:\n#{log_contents.join}")
  end

  def expected_worker_name(worker_pid)
    "host:#{Socket.gethostname} pid:#{worker_pid}"
  end

  def child_worker_pids
    return [] unless File.exists?(worker_state_file)

    state = IO.read(worker_state_file)
    state.present? ? JSON.parse(state) : []
  end

  def kill_process(pid, signal = 'TERM')
    Process.kill(signal, pid)
  rescue Errno::ESRCH
    puts "WARNING: Process #{pid} already killed"
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_for_process_terminated(pid)
    Wait.for("process #{pid} terminated") do
      !process_alive?(pid)
    end
  end

  def queue_create_file_job(file, queue: nil)
    with_test_app_database_connection do
      Delayed::Job.enqueue(TouchFileJob.new(file), queue: queue)
    end
  end

  def with_test_app_database_connection
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: test_app_database, timeout: 1000)
    yield
  ensure
    ActiveRecord::Base.connection_pool.disconnect!
  end

  def setup_test_app_database
    output, status = Open3.capture2e(worker_pool_env, 'rake db:drop && rake db:setup', chdir: test_app_root)
    unless status.success?
      raise "Failed to setup test app database:\n#{output}"
    end
  end

  def log_worker_pool_output(example)
    File.open(File.join(log_dir, "worker-pool-#{master_pid}.log"), 'w') do |log|
      log.puts("Worker pool output for #{example.location}")
      IO.copy_stream(@master_stdout_err, log)
    end
  rescue ThreadShutdownException
    # We're being forcefully shutdown
  rescue => e
    puts "WARNING: Log thread failed: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def worker_pool_env(num_workers: nil, queues: nil)
    env = ENV.to_h
    env['NUM_WORKERS'] = num_workers.to_s if num_workers
    env['QUEUES'] = queues.join(',') if queues
    env['RAILS_ENV'] = 'development'
    env['MASTER_CALLBACK_LOG'] = master_callback_log
    env['WORKER_CALLBACK_LOG'] = worker_callback_log
    env['WORKER_STATE_FILE'] = worker_state_file
    env
  end

  def parse_callback_log(file)
    IO.readlines(file).map { |line| JSON.parse(line).symbolize_keys }
  end

  def master_callback_log
    File.expand_path(File.join(jobs_dir, 'master_callbacks.log'))
  end

  def worker_callback_log
    File.expand_path(File.join(jobs_dir, 'worker_callbacks.log'))
  end

  def worker_state_file
    File.expand_path(File.join(jobs_dir, 'worker_state.json'))
  end

  def log_dir
    File.expand_path(File.join('tmp', 'log'))
  end

  def jobs_dir
    File.expand_path(File.join('tmp', 'jobs'))
  end

  def config_file_path(basename)
    File.expand_path(File.join('spec', 'config', basename))
  end

  def test_app_database
    "#{test_app_root}/db/development.sqlite3"
  end

  def test_app_root
    File.expand_path(File.join('spec', 'dummy'))
  end

  ThreadShutdownException = Class.new(StandardError)
end
