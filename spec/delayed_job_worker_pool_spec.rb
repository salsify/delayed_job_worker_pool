require 'spec_helper'
require 'open3'
require 'active_record'
require 'active_support/all'
require 'delayed_job_active_record'
require_relative 'dummy/app/jobs/touch_file_job'

describe DelayedJobWorkerPool do
  let(:config_file) { config_file_path('preload_app.rb') }

  before(:all) do
    setup_test_app_database
  end

  before do |example|
    @master_pid = start_worker_pool(example, config_file)
  end

  after do
    kill_process(@master_pid)
    FileUtils.remove_dir(jobs_dir, force: true)
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

  context 'when the app is not preloaded' do
    let(:config_file) { config_file_path('postload_app.rb') }

    it_behaves_like 'runs jobs on active queues'
  end

  context 'when children fail' do
    before do
      Wait.for('children started') do
        child_worker_pids.present?
      end

      # Kill the initially booted workers so the master will restart them
      child_worker_pids.each do |child_worker_pid|
        kill_process(child_worker_pid, 'KILL')
      end
    end

    it_behaves_like 'runs jobs on active queues'
  end

  it 'exits workers if the master process dies' do
    Wait.for('children started') do
      child_worker_pids.present?
    end

    orphaned_pids = child_worker_pids

    kill_process(@master_pid, 'KILL')

    orphaned_pids.each do |orphaned_pid|
      Wait.for('child terminated') do
        process_alive?(orphaned_pid)
      end
    end
  end

  def start_worker_pool(example, config_file, num_workers: 1, queues: ['active'])
    env = worker_pool_env(num_workers: num_workers, queues: queues)
    _, stdout_err, wait_thread = Open3.popen2e(env, 'delayed_job_worker_pool', config_file, chdir: test_app_root)
    pid = wait_thread[:pid]
    Thread.new do
      log_worker_pool_output(example, pid, stdout_err)
    end
    pid
  end

  def child_worker_pids
    `pgrep -P #{@master_pid}`.split.map(&:to_i)
  end

  def kill_process(pid, signal = 'TERM')
    Process.kill(signal, pid)
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
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

  def log_worker_pool_output(example, pid, io)
    FileUtils.makedirs('log')
    File.open("log/worker-pool-#{pid}.log", 'w') do |log|
      log.puts("Worker pool output for #{example.location}")
      while line = io.gets
        log.puts(line)
      end
    end
  end

  def worker_pool_env(num_workers: nil, queues: nil)
    env = ENV.to_h
    env['NUM_WORKERS'] = num_workers.to_s if num_workers
    env['QUEUES'] = queues.join(',') if queues
    env['RAILS_ENV'] = 'development'
    env
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
