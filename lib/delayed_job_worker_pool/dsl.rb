module DelayedJobWorkerPool
  class DSL
    class NoWorkerGroupsDefined < StandardError; end
    class NonUniqueGroupName < StandardError; end

    CALLBACK_SETTINGS = [:after_preload_app, :on_worker_boot, :after_worker_boot, :after_worker_shutdown].freeze
    DEFAULT_WORKER_GROUP_NAME = :default

    def self.load(path)
      options = {}

      dsl = new(options)
      dsl.instance_eval(File.read(path), path, 1)
      dsl.assert_groups_defined!

      options
    end

    def initialize(options)
      @options = options
      @options[:worker_groups] ||= {}
    end

    def preload_app(preload = true)
      @options[:preload_app] = preload
    end

    def worker_group(name = DEFAULT_WORKER_GROUP_NAME, &block)
      name_sym = name.to_sym
      if @options[:worker_groups].key?(name_sym)
        raise NonUniqueGroupName, "Worker group name #{name_sym} is already in use"
      end

      group_options = WorkerGroupOptions.new
      yield(group_options)
      @options[:worker_groups][name_sym] = group_options
    end

    def assert_groups_defined!
      return unless @options[:worker_groups].empty?

      raise NoWorkerGroupsDefined,
            'No worker groups defined. Define groups using `worker_group`.'
    end

    CALLBACK_SETTINGS.each do |option_name|
      define_method(option_name) do |&block|
        @options[option_name] = block
      end
    end
  end
end
