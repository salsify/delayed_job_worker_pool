# frozen_string_literal: true

require 'spec_helper'

describe DelayedJobWorkerPool::WorkerGroupOptions do
  let(:options) { DelayedJobWorkerPool::WorkerGroupOptions.new }

  it '#dj_worker_options' do
    expect(options.dj_worker_options).to eq({})

    options.queues = nil
    options.workers = 5

    expect(options.dj_worker_options).to eq({})

    options.queues = ['foo']
    expect(options.dj_worker_options).to eq({ queues: ['foo'] })
  end
end
