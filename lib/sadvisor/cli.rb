require 'json'
require 'ostruct'
require 'thor'
require 'yaml'

module Sadvisor
  class SadvisorCLI < Thor
    desc 'workload NAME', 'run the workload NAME'
    option :max_space, type: :numeric, default: Float::INFINITY
    option :format, type: :string, default: 'text'
    def workload(name)
      # rubocop:disable GlobalVars

      is_text = options[:format] == 'text'

      require_relative "../../workloads/#{name}"

      if options[:max_space].finite?
        indexes = Sadvisor::Search.new($workload) \
          .search_overlap(options[:max_space])
      else
        # No need to search here, we'll prune to the used indices later
        indexes = Sadvisor::IndexEnumerator.new($workload) \
          .indexes_for_workload.to_a
      end

      simple_indexes = $workload.entities.values.map(&:simple_index)
      planner = Sadvisor::Planner.new $workload, (indexes + simple_indexes)
      plans = {}
      $workload.queries.each do |query|
        plans[query] = planner.min_plan query
      end

      indexes = plans.values.map(&:to_a).flatten.select do |step|
        step.is_a? Sadvisor::IndexLookupPlanStep
      end.map(&:index).to_set

      header = "Indexes\n" + '━' * 50
      puts $stdout.isatty ? header.blue : header if is_text
      (simple_indexes.to_set + indexes).each do |index|
        puts index.inspect
      end if is_text
      puts if is_text

      total_size = (indexes - simple_indexes).map(&:size).inject(0, :+)
      puts ($stdout.isatty ? 'Total size: '.blue : 'Total size: ') + \
        total_size.to_s if is_text
      puts if is_text

      # Output queries plans for the discovered indices
      header = "Query plans\n" + '━' * 50
      puts $stdout.isatty ? header.blue : header if is_text
      plans.each do |query, plan|
        puts query.inspect if is_text
        puts plan.inspect if is_text
        puts if is_text
      end

      if options[:format] == 'json'
        result = OpenStruct.new(
          workload: $workload,
          indexes: indexes,
          plans: plans.values,
          total_size: total_size,
          total_cost: $workload.query_weights.map do |query, weight|
            weight * plans[query].cost
          end.inject(0, &:+)
        )

        puts JSON.pretty_generate \
          Sadvisor::SearchResultRepresenter.represent(result).to_hash
      end

      # rubocop:enable GlobalVars
    end

    desc 'repl PLAN_FILE', 'start the REPL with the given PLAN_FILE'
    def repl(plan_file)
      result = load_results plan_file

      loop do
        line = get_line
        break if line.nil?
        line.chomp!
        query = Statement.new line, result.workload

        # Print the plan corresponding to the query
        p result.plans.find { |plan| plan.query == query }
      end
    end

    desc 'create PLAN_FILE', 'create indexes from the given PLAN_FILE'
    def create(plan_file)
      result = load_results(plan_file)
      config = load_config

      require_relative "backends/#{config[:database]}"
      be_class_name = ['Sadvisor', config[:database].capitalize + 'Backend']
      backend = be_class_name.reduce(Object) do |mod, name_part|
        mod.const_get name_part
      end.new(result.workload, result.indexes, result.plans, **config)

      backend.indexes_ddl.each do |ddl|
        puts ddl
      end
    end

    private

    # Load the configuration to use for a backend
    def load_config
      config = YAML.load_file File.join(Dir.pwd, 'sadvisor.yml')
      Hash[config.map { |k, v| [k.to_sym, v] }]
    end

    # Load results of a previous search operation
    def load_results(plan_file)
      representer = Sadvisor::SearchResultRepresenter.represent(OpenStruct.new)
      json = File.read(plan_file)
      representer.from_json(json)
    end

    # Get the next inputted line in the REPL
    def get_line
      prefix = '>> '

      begin
        require 'readline'
        line = Readline.readline prefix
        return if line.nil?

        Readline::HISTORY.push line
      rescue LoadError
        print prefix
        line = gets
      end

      line
    end
  end
end
