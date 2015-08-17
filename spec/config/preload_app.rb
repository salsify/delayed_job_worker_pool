workers Integer(ENV.fetch('NUM_WORKERS', 1))
queues ENV.fetch('QUEUES', '').split(',')
sleep_delay 0.1

preload_app
