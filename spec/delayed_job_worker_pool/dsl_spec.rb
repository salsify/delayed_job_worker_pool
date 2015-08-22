require 'spec_helper'

describe DelayedJobWorkerPool::DSL do

  describe ".load" do
    DelayedJobWorkerPool::DSL::SIMPLE_SETTINGS.each do |setting|
      it "parses #{setting}" do
        options = process_dsl <<-DSL
          #{setting} 'foo'
        DSL

        expect(options).to eq(setting => 'foo')
      end
    end

    it "ignores nil settings" do
      options = process_dsl <<-DSL
        workers nil
      DSL

      expect(options).to be_empty
    end

    it "parses preload_app without any args" do
      options = process_dsl <<-DSL
        preload_app
      DSL

      expect(options).to eq(preload_app: true)
    end

    it "parses preload_app with args" do
      options = process_dsl <<-DSL
        preload_app false
      DSL

      expect(options).to eq(preload_app: false)
    end

    DelayedJobWorkerPool::DSL::CALLBACK_SETTINGS.each do |setting|
      it "parses #{setting}" do
        options = process_dsl <<-DSL
          #{setting} do
            '#{setting}-value'
          end
        DSL

        expect(options[setting].call).to eq "#{setting}-value"
      end
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
