# frozen_string_literal: true

module DelayedJobWorkerPool
  # Keeps track of worker groups and their workers.
  class Registry
    class GroupAlreadyExists < StandardError; end
    class GroupDoesNotExist < StandardError; end
    class GroupNotFound < StandardError; end

    def initialize
      @groups = {}
    end

    def include_worker?(pid)
      worker_pids.include?(pid)
    end

    def has_workers?
      !worker_pids.empty?
    end

    def add_group(name, options)
      raise GroupAlreadyExists.new("Group #{group} already exists") if @groups.key?(name)

      @groups[name] = {
        options: options,
        pids: []
      }
    end

    def add_worker(group_name, pid)
      group_by_name(group_name)[:pids] << pid
    end

    def remove_worker(pid)
      @groups[group(pid)][:pids].delete(pid)
    end

    def options(group_name)
      group_by_name(group_name)[:options]
    end

    def worker_pids
      @groups.values.flat_map { |v| v[:pids] }
    end

    def group(pid)
      @groups.each do |name, group|
        return name if group[:pids].include?(pid)
      end
      raise GroupNotFound.new("No group found for PID #{pid}")
    end

    private

    def group_by_name(name)
      match = @groups[name]
      return match unless match.nil?

      raise GroupDoesNotExist.new("No group with name #{name.inspect} found")
    end
  end
end
