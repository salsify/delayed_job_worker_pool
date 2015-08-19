# Delayed Job Worker Pool

[![Gem Version](https://badge.fury.io/rb/delayed_job_worker_pool.png)][gem]
[![Build Status](https://secure.travis-ci.org/salsify/delayed_job_worker_pool.png?branch=master)][travis]
[![Code Climate](https://codeclimate.com/github/salsify/delayed_job_worker_pool.png)][codeclimate]

[gem]: https://rubygems.org/gems/delayed_job_worker_pool
[travis]: http://travis-ci.org/salsify/delayed_job_worker_pool
[codeclimate]: https://codeclimate.com/github/salsify/delayed_job_worker_pool

[Delayed Job's](https://github.com/collectiveidea/delayed_job) built-in worker pooling daemonizes all worker processes. This is great for certain environments but not so great for environments like Heroku that really want your processes to run in the foreground. Delayed Job Worker Pool runs a pool of Delayed Job workers **without** daemonizing them. [Salsify](http://salsify.com) is currently using this to run multiple Delayed Job workers on a single Heroku PX dyno.
 
This gem only works with MRI on Linux/MacOS X.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'delayed_job_worker_pool'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install delayed_job_worker_pool

## Usage

From your Rails root directory run:

```
delayed_job_worker_pool <config file>
```

The config file is a Ruby DSL inspired by the [Puma](https://github.com/puma/puma) configuration DSL. Here's an example:

```
workers Integer(ENV['NUM_WORKERS'] || 1)
queues (ENV['QUEUES'] || ENV['QUEUE'] || '').split(',')
sleep_delay ENV['WORKER_SLEEP_DELAY']

preload_app

after_preload_app do
  puts "Master #{Process.pid} preloaded app"
  
  # Don't hang on to database connections from the master after we've completed initialization
  ActiveRecord::Base.connection_pool.disconnect!
end

on_worker_boot do
  puts "Worker #{Process.pid} started"
  
  # Reconnect to the database
  ActiveRecord::Base.establish_connection
end

after_worker_boot do |worker_pid|
  puts "Master #{Process.pid} booted worker #{worker_pid}"
end

after_worker_shutdown do |worker_pid|
  puts "Master #{Process.pid} detected dead worker #{worker_pid}"
end
```

Here's more information on each setting:

* `workers` - The number of Delayed Job worker processes to fork. The master process will relaunch workers that fail.
* Delayed Job worker settings (`queues`, `min_priority`, `max_priority`, `sleep_delay`, `read_ahead`) - These are passed through to the Delayed Job worker.
* `preload_app` - This forces the master process to load Rails before forking worker processes causing the memory consumed by the code to be shared between workers. **If you use this setting make sure you re-establish any necessary connections in the on_worker_boot callback.**
* `after_preload_app` - A callback that runs in the master process after preloading the app but before forking any workers.
* `on_worker_boot` - A callback that runs in the worker process after it has been forked.
* `after_worker_boot` - A callback that runs in the master process after a worker has been forked.
* `after_worker_shutdown` - A callback that runs in the master process after a worker has been shutdown.

All settings are optional and nil values are ignored. 

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/salsify/delayed_job_worker_pool.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

