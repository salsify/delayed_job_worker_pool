# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'delayed_job_worker_pool'

Dir['spec/support/**/*.rb'].each { |f| require File.expand_path(f) }
