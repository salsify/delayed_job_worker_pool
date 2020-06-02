worker_group(:default) do |g|
  g.workers = Integer(ENV.fetch('NUM_WORKERS', 1))
  g.queues = ENV.fetch('QUEUES', '').split(',')
  g.sleep_delay = 0.1
end

preload_app

master_callback_log = ENV.fetch('MASTER_CALLBACK_LOG')
worker_callback_log = ENV.fetch('WORKER_CALLBACK_LOG')
worker_state_file = ENV.fetch('WORKER_STATE_FILE')

def write_callback_log(log, callback, worker_info = nil)
  payload = { callback: callback, pid: Process.pid }
  if worker_info
    payload.merge!(
      worker_pid: worker_info.process_id,
      worker_name: worker_info.name,
      worker_group: worker_info.worker_group
    )
  end
  IO.write(log, "#{payload.to_json}\n", mode: 'a')
end

def write_worker_state_file(worker_state_file, worker_pids)
  IO.write(worker_state_file, worker_pids.to_json)
end

worker_pids = []

after_preload_app do
  write_callback_log(master_callback_log, :after_preload_app)
end

on_worker_boot do |worker_info|
  write_callback_log(worker_callback_log, :on_worker_boot, worker_info)
end

after_worker_boot do |worker_info|
  write_callback_log(master_callback_log, :after_worker_boot, worker_info)
  worker_pids << worker_info.process_id
  write_worker_state_file(worker_state_file, worker_pids)
end

after_worker_shutdown do |worker_info|
  write_callback_log(master_callback_log, :after_worker_shutdown, worker_info)
  worker_pids.delete(worker_info.process_id)
  write_worker_state_file(worker_state_file, worker_pids)
end
