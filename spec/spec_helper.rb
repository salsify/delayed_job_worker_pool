$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'delayed_job_worker_pool'

Dir['spec/support/**/*.rb'].each { |f| require File.expand_path(f) }
