worker_group(:group_1) do |g|
  g.workers = 1
  g.queues = ENV.fetch('QUEUES_GROUP_1').split(',')
  g.sleep_delay = 0.1
end

worker_group(:group_2) do |g|
  g.workers = 1
  g.queues = ENV.fetch('QUEUES_GROUP_2').split(',')
  g.sleep_delay = 0.1
end

preload_app
