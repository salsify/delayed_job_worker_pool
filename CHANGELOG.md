# Changelog

### 1.0.0
* Require Ruby 2.7 or higher.

### 0.3.0
* Require Ruby 2.5 or higher.
* Support for running multiple worker pools on a single node. 
  See [#7](https://github.com/salsify/delayed_job_worker_pool/pull/7) for details.
  Thanks to Severin Räz!

### 0.2.3
* Explicitly require 'fcntl' to fix uninitialized constant IO::Fcntl. Thanks to Stefan Wrobel!

### 0.2.2
* Add support for Delayed Job 4.1

### 0.2.1
* Fix race condition in signal handler
