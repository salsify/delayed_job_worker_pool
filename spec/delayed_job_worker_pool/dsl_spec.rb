# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

describe DelayedJobWorkerPool::DSL do

  describe ".load" do
    describe "worker pools" do
      it "parses worker_group blocks" do
        options = process_dsl <<-DSL
          worker_group do |g|
            g.workers = 4
          end

          worker_group(:a) do |g|
            g.workers = 5
          end

          worker_group('b') do |g|
            g.workers = 6
          end
        DSL

        groups = options[:worker_groups]
        expect(groups.keys).to eq([:default, :a, :b])
        expect(groups[:default].workers).to eq(4)
        expect(groups[:a].workers).to eq(5)
        expect(groups[:b].workers).to eq(6)
      end
    end

    describe "preload_app" do
      it "parses preload_app without any args" do
        options = process_global_dsl <<-DSL
          preload_app
        DSL

        expect(options[:preload_app]).to be_truthy
      end

      it "parses preload_app with args" do
        options = process_global_dsl <<-DSL
          preload_app false
        DSL

        expect(options[:preload_app]).to be_falsey
      end
    end

    DelayedJobWorkerPool::DSL::CALLBACK_SETTINGS.each do |setting|
      it "parses #{setting}" do
        options = process_global_dsl <<-DSL
          #{setting} do
            '#{setting}-value'
          end
        DSL

        expect(options[setting].call).to eq "#{setting}-value"
      end
    end

    def process_global_dsl(input)
      # Add default worker pool to make DSL valid
      process_dsl <<-DSL
        worker_group(:group) { |g| }
        #{input}
      DSL
    end

    def process_dsl(input)
      Tempfile.open('dsl') do |file|
        file.write(input)
        file.close
        DelayedJobWorkerPool::DSL.load(file.path)
      end
    end
  end

end
