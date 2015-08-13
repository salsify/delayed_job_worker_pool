module DelayedJobWorkerPool
  class DSL
    SIMPLE_SETTINGS = [:workers, :queues, :min_priority, :max_priority, :sleep_delay, :read_ahead].freeze
    CALLBACK_SETTINGS = [:before_worker_boot, :on_worker_boot, :after_worker_boot].freeze

    def self.load(path)
      options = {}

      dsl = new(options)
      dsl.instance_eval(File.read(path), path, 1)

      options
    end

    def initialize(options)
      @options = options
    end

    SIMPLE_SETTINGS.each do |option_name|
      define_method(option_name) do |option_value|
        @options[option_name] = option_value unless option_value.nil?
      end
    end

    def preload_app(preload_app = true)
      @options[:preload_app] = preload_app
    end

    CALLBACK_SETTINGS.each do |option_name|
      define_method(option_name) do |&block|
        @options[option_name] = block
      end
    end
  end
end
