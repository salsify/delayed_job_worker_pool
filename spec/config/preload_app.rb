workers Integer(ENV.fetch('NUM_WORKERS', 1))
queues ENV.fetch('QUEUES', '').split(',')
sleep_delay 0.1

preload_app

master_callback_log = ENV.fetch('MASTER_CALLBACK_LOG')
worker_callback_log = ENV.fetch('WORKER_CALLBACK_LOG')

def write_callback_log(log, callback, payload = {})
  payload = payload.merge(callback: callback, pid: Process.pid)
  IO.write(log, "#{payload.to_json}\n", mode: 'a')
end

after_preload_app do
  write_callback_log(master_callback_log, :after_preload_app)
end

on_worker_boot do
  write_callback_log(worker_callback_log, :on_worker_boot)
end

after_worker_boot do |worker_pid|
  write_callback_log(master_callback_log, :after_worker_boot, worker_pid: worker_pid)
end

after_worker_shutdown do |worker_pid|
  write_callback_log(master_callback_log, :after_worker_shutdown, worker_pid: worker_pid)
end
