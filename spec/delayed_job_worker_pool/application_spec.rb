require 'spec_helper'

describe DelayedJobWorkerPool::Application do
  describe ".load" do
    it "doesn't raise an exception when the application file is present" do
      allow(DelayedJobWorkerPool::Application).to receive(:require).with("#{Dir.pwd}/config/environment")
      expect { DelayedJobWorkerPool::Application.load }.not_to raise_error
    end

    it "raises an exception when the application file is not present" do
      expect { DelayedJobWorkerPool::Application.load }.to raise_error
    end
  end
end
