# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'active_record'
require 'active_support/all'
require 'delayed_job_active_record'
require_relative 'dummy/app/jobs/touch_file_job'

describe DelayedJobWorkerPool do
  let(:shutdown_exception) { Class.new(StandardError) }
  let(:config_file) { config_file_path('preload_app.rb') }
  let(:worker_pool_env) do
    make_worker_pool_env
      .merge({ 'NUM_WORKERS' => '1', 'QUEUES' => 'active' })
  end

  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    FileUtils.makedirs(log_dir)
    setup_test_app_database
  end

  before do |example|
    FileUtils.remove_dir(jobs_dir, true)
    FileUtils.makedirs(jobs_dir)
    start_worker_pool(example, config_file, worker_pool_env)
  end

  after do
    shutdown_worker_pool
    FileUtils.remove_dir(jobs_dir, true)
  end

  shared_examples "runs jobs on active queues" do
    specify do
      inactive_job_file = "#{jobs_dir}/inactive.txt"
      queue_create_file_job(inactive_job_file, queue: 'inactive')

      active_job_file = "#{jobs_dir}/active.txt"
      queue_create_file_job(active_job_file, queue: 'active')

      Wait.for('job completed') do
        File.exist?(active_job_file)
      end

      expect(File).not_to exist(inactive_job_file)
    end
  end

  it_behaves_like "runs jobs on active queues"

  it "invokes after_preload_app, on_worker_boot, and after_worker_boot callbacks" do
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
          worker_name: expected_worker_name(worker_pid),
          worker_group: 'default'
      }
    ]

    wait_for_num_log_lines(worker_callback_log, 1)
    expect(parse_callback_log(worker_callback_log)).to eq [
      {
          callback: 'on_worker_boot',
          pid: worker_pid,
          worker_pid: worker_pid,
          worker_name: expected_worker_name(worker_pid),
          worker_group: 'default'
      }
    ]
  end

  context "when the app is not preloaded" do
    let(:config_file) { config_file_path('postload_app.rb') }

    it_behaves_like "runs jobs on active queues"
  end

  context "multiple worker groups" do
    let(:worker_pool_env) do
      make_worker_pool_env.merge(
        {
          'QUEUES_GROUP_1' => first_group_queues,
          'QUEUES_GROUP_2' => second_group_queues
        }
      )
    end

    let(:config_file) { config_file_path('multiple_groups.rb') }

    context "first group gets its options" do
      let(:first_group_queues) { 'active' }
      let(:second_group_queues) { 'other' }

      it_behaves_like "runs jobs on active queues"
    end

    context "second group gets its options" do
      let(:first_group_queues) { 'other' }
      let(:second_group_queues) { 'active' }

      it_behaves_like "runs jobs on active queues"
    end
  end

  context "when children fail" do
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

    it_behaves_like "runs jobs on active queues"

    it "invokes after_worker_shutdown callbacks" do
      wait_for_children_booted
      wait_for_num_log_lines(master_callback_log, 1 + 3 * @killed_worker_pids.size)

      callback_messages = parse_callback_log(master_callback_log)
      @killed_worker_pids.each do |killed_worker_pid|
        expect(callback_messages).to include({
            callback: 'after_worker_shutdown',
            pid: master_pid,
            worker_pid: killed_worker_pid,
            worker_name: expected_worker_name(killed_worker_pid),
            worker_group: 'default'
        })
      end
    end
  end

  it "exits workers if the master process dies" do
    worker_pids = wait_for_children_booted

    kill_process(master_pid, 'KILL')

    worker_pids.each do |worker_pid|
      Wait.for('child terminated') do
        process_alive?(worker_pid)
      end
    end
  end

  def start_worker_pool(example, config_file, env)
    stdin, @master_stdout_err, @master_thread = Open3.popen2e(
      env,
      'delayed_job_worker_pool',
      config_file,
      chdir: test_app_root
    )
    stdin.close
    @master_log_thread = Thread.new do
      log_worker_pool_output(example)
    end
  end

  def shutdown_worker_pool
    if process_alive?(master_pid)
      kill_process(master_pid, 'TERM')
      begin
        Process.wait(master_pid)
      rescue StandardError
        Errno::ECHILD
      end
    end

    @master_stdout_err.close if @master_stdout_err

    if @master_log_thread && !@master_log_thread.join(2)
      puts 'WARNING: Failed to gracefully join master_log_thread'
      @master_log_thread.raise(shutdown_exception.new)
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
      if File.exist?(log)
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
    "host:#{Socket.gethostname} pid:#{worker_pid} group:default"
  end

  def child_worker_pids
    return [] unless File.exist?(worker_state_file)

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
    output, status = Open3.capture2e(make_worker_pool_env, 'rails db:reset', chdir: test_app_root)
    raise "Failed to setup test app database:\n#{output}" unless status.success?
  end

  def log_worker_pool_output(example)
    File.open(File.join(log_dir, "worker-pool-#{master_pid}.log"), 'w') do |log|
      log.puts("Worker pool output for #{example.location}")
      IO.copy_stream(@master_stdout_err, log)
    end
  rescue shutdown_exception
    # We're being forcefully shutdown
  rescue StandardError => e
    puts "WARNING: Log thread failed: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
  end

  def make_worker_pool_env
    env = ENV.to_h
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
end
