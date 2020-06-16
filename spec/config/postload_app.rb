worker_group(:default) do |g|
  g.workers = Integer(ENV.fetch('NUM_WORKERS', 1))
  g.queues = ENV.fetch('QUEUES', '').split(',')
  g.sleep_delay = 0.1
end
