# frozen_string_literal: true

require 'spec_helper'

describe DelayedJobWorkerPool::Registry do
  let(:registry) { DelayedJobWorkerPool::Registry.new }

  context "empty registry" do
    it '#workers?' do
      expect(registry).not_to be_workers
    end

    it "adds groups and workers" do
      registry.add_group(:group_a, {})
      registry.add_worker(:group_a, 1)
      expect(registry.worker_pids).to eq([1])
      registry.add_worker(:group_a, 2)
      expect(registry.worker_pids).to eq([1, 2])

      registry.add_group(:group_b, {})
      registry.add_worker(:group_b, 3)
      expect(registry.worker_pids).to eq([1, 2, 3])
    end
  end

  context "registry with workers" do
    before do
      registry.add_group(:group_a, { id: :options_a })
      registry.add_worker(:group_a, 1)
      registry.add_worker(:group_a, 2)

      registry.add_group(:group_b, { id: :options_b })
      registry.add_worker(:group_b, 3)
    end

    it '#add_worker raises when group does not exist' do
      expect { registry.add_worker(:unknown_group, 1) }.to raise_error(
        DelayedJobWorkerPool::Registry::GroupDoesNotExist
      )
    end

    it '#workers?' do
      expect(registry).to be_workers
    end

    it '#include_worker?' do
      expect(registry).to be_include_worker(1)
      expect(registry).to be_include_worker(3)
      expect(registry).not_to be_include_worker(4)
    end

    it '#group' do
      expect(registry.group(1)).to eq(:group_a)
      expect(registry.group(3)).to eq(:group_b)

      expect { registry.group(10) }.to raise_error(
        DelayedJobWorkerPool::Registry::GroupNotFound
      )
    end

    it '#options' do
      expect(registry.options(:group_a)).to eq({ id: :options_a })
      expect(registry.options(:group_b)).to eq({ id: :options_b })
    end

    it '#options raises when group does not exist' do
      expect { registry.options(:bogus_group) }.to raise_error(
        DelayedJobWorkerPool::Registry::GroupDoesNotExist
      )
    end

    it "removes workers" do
      registry.remove_worker(1)
      expect(registry.worker_pids).to eq([2, 3])
      registry.remove_worker(3)
      expect(registry.worker_pids).to eq([2])
    end
  end
end
