workers Integer(ENV.fetch('NUM_WORKERS', 1))
queues ENV.fetch('QUEUES', '').split(',')
sleep_delay 0.1

preload_app

master_callback_log = ENV.fetch('MASTER_CALLBACK_LOG')
worker_callback_log = ENV.fetch('WORKER_CALLBACK_LOG')

def write_callback_log(log, callback, worker_info = nil)
  payload = { callback: callback, pid: Process.pid }
  payload.merge!(worker_pid: worker_info.process_id, worker_name: worker_info.name) if worker_info
  IO.write(log, "#{payload.to_json}\n", mode: 'a')
end

after_preload_app do
  write_callback_log(master_callback_log, :after_preload_app)
end

on_worker_boot do |worker_info|
  write_callback_log(worker_callback_log, :on_worker_boot, worker_info)
end

after_worker_boot do |worker_info|
  write_callback_log(master_callback_log, :after_worker_boot, worker_info)
end

after_worker_shutdown do |worker_info|
  write_callback_log(master_callback_log, :after_worker_shutdown, worker_info)
end
