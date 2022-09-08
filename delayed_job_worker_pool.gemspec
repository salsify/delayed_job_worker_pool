# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'delayed_job_worker_pool/version'

Gem::Specification.new do |spec|
  spec.name          = 'delayed_job_worker_pool'
  spec.version       = DelayedJobWorkerPool::VERSION
  spec.authors       = ['Joel Turkel']
  spec.email         = ['jturkel@salsify.com']

  spec.summary       = 'Worker process pooling for Delayed Job'
  spec.homepage      = 'https://github.com/salsify/delayed_job_worker_pool'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org'
    spec.metadata['rubygems_mfa_required'] = 'true'
  else
    raise 'RubyGems 2.0 or newer is required to set allowed_push_host.'
  end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables   = ['delayed_job_worker_pool']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.5'

  spec.add_dependency 'delayed_job', ['>= 3.0', '< 4.2']

  spec.add_development_dependency 'appraisal'
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'delayed_job_active_record'
  spec.add_development_dependency 'rails', '>= 5.2', '< 8'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '>= 3.8'
  spec.add_development_dependency 'rspec_junit_formatter'
  spec.add_development_dependency 'salsify_rubocop', '~> 1.0.2'
  spec.add_development_dependency 'sprockets', '< 4'
  spec.add_development_dependency 'sqlite3', '>= 1.3'
end
