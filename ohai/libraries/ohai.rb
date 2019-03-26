class OhaiResource < Inspec.resource(1)
  name 'ohai'

  example <<~EXAMPLE
    describe ohai do
      its('uptime_seconds') { should be > 360 }
    end
  EXAMPLE

  def initialize(ohai_path_override_or_options = {})
    # TODO: Compare options against a list of valid option names and throw errors
    #   when one is not defined to prevent users from losing hours to misspellings
    options = if ohai_path_override_or_options.is_a?(String)
      { path: ohai_path_override_or_options }
    else
      ohai_path_override_or_options
    end

    @ohai_path_override = options[:path]

    # NOTE: Other options could also be provided to pass along to the execution

    # NOTE: Plugins and plugin paths could also be specifed as an option on creation
    #   because not running all the plugins would make for a faster executing resource
    
    # TODO: If more than one attribute is provided it displays the outputs one right after
    #   the other and that makes it a more time-consuming processing to JSON parse. Some regex
    #   splitting or more intelligent parsing would have to be developed.
    @ohai_attributes = Array(options[:attribute] || options['attribute'])
  end

  def version
    # TODO: It would be good to see how far back this version string format is supported
    inspec.command("#{ohai_path} --version").stdout.strip.split(": ").last
  end

  def ohai_results
    @ohai_results ||= load_results
  end

  private

  def method_missing(name,*args,&block)
    if ohai_results
      if ohai_results.key?(name)
        ohai_results[name]
      else
        # TODO: Create a better error message to make it clear that these are the top-level keys
        raise "The Ohai results do not have attribute '#{name}'. Ohai did find: #{ohai_results.keys}"
      end
    else
      # Default to the usual method_missing when there are no results.
      super
    end
  end

  def ohai_path
    @resolved_ohai_path ||= begin
      path = @ohai_path_override || find_ohai_path_on_target
      # TODO: Better error that describes that no/empty path provided
      #   or the strategy used to find it. Other resources must do this use their work
      raise 'Ohai Not Found' if path.nil? || path.empty?
      path
    end
  end

  def find_ohai_path_on_target
    # TODO: provide support for all platforms and other strageties
    inspec.command('which ohai').stdout.chomp
  end

  def build_ohai_command
    cmd = "#{ohai_path}"
    cmd += " #{@ohai_attributes.join(' ')}" unless @ohai_attributes.empty?
    cmd
  end

  #
  # When the ohai command is given more than a single attribute the resulting output is
  # two valid JSON objects next to one another in the output. An example:
  #
  #     $ ohai os chef_packages
  #     [
  #       "darwin"
  #     ]
  #     {
  #       "chef": {
  #         "version": "14.11.21",
  #         "chef_root": "/Users/.../lib"
  #       },
  #       "ohai": {
  #         "version": "14.8.10",
  #         "ohai_root": "/Users/.../ohai"
  #       }
  #     }
  #
  # This code will split the output by the terminating character
  # for an array or hash. This puts the data and its closing separator into 
  # an array as elements next to one another. Looking at them in pairs of two (#each_slice)
  # we bring them back together.
  def partition_results(output)
    output.strip.split(/(^[\]\}])/).each_slice(2).map {|result| result.join }
  end

  # Run the ohai command provided at the path, process the results and cache the data for
  # future resources to use.
  #
  # TODO: This function does three things: loads the results, processes the results, and 
  #    caches the results. Move the caching outside at least and move that into its own step
  # 
  # @param path the path to the ohai executable when invoked will generate the JSON results
  # @return the
  def load_results
    result = inspec.command(build_ohai_command).result
    # TODO: Include stderr and other information in the failure case
    raise "Ohai #{ohai_path} failed to execute (#{result.exit_status})" if result.exit_status != 0
    
    partitioned_results = partition_results(result.stdout)

    # TODO: A JSON::ParserError is thrown here when the JSON is incorrect but the resulting error
    #   message does not inclue a lot of information to make it easy to find out what is going on
    #   so it may be important to make a new error that shows the command executed. The resulting
    #   standard out and then display the error. It would also be nice if inspec provided a place
    #   locally when this error message is so big.
    parsed_results = partitioned_results.map do |result|
      JSON.parse(result)
    end

    raw_code_object_results = if @ohai_attributes.empty?
      parsed_results.first
    else
      attribute_with_results = @ohai_attributes.each_with_index.map do |attribute, index|
        matching_results = parsed_results[index]
        matching_results = Array(matching_results).first if Array(matching_results).count == 1
        { "#{attribute}": matching_results }
      end

      attribute_with_results.reduce({}, :merge)
    end
    
    # TODO: The lower-level keys return the Hashie::Mash which probably produces
    #   very meaningless errors as well that could be improved.
    results = OhaiMash.new( raw_code_object_results )

    results
  end

  # Creating a subclass of the Hashie::Mash because that is the only place
  # in which it is safe for you to disable warnings when the data structure defines keys
  # that have similar names ass methods that important for Hashie::Mash.
  #
  # In the case of Ohai results the `counters` and `kernel` sections contain:
  #     drop, index and size
  #
  # Because this data is going to be read-only overwriting seems safe.
  class OhaiMash < Hashie::Mash
    disable_warnings
  end
end