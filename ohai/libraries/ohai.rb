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

    @ohai_attributes = Array(options[:attribute] || options['attribute'])

    @ohai_directories = Array(options[:directory] || options['directory'])
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

    @ohai_directories.each do |dir|
      cmd += " --directory #{dir}"
    end

    @ohai_attributes.each do |attribute|
      cmd += " #{attribute}"
    end

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
        
        # The attribute itself may be a compounded key separated by forward-slashes.
        # So we need to build a hash and have a pointer to the root,
        # the lasst hash and the final key to be added
        root, last_hash, last_key = expand_attribute(attribute)
        last_hash[last_key] = matching_results
        root
      end
      
      # The results coming could be hashes that contain conflicting keys
      # so the hashes will need to be deep-merged.
      attribute_with_results.reduce({}) { |acc,cur| deep_merge(acc, cur) }
    end
    
    # TODO: Using an OhaiMash (Hashie::Mash) is an easy way to get dot-notation
    #   however, it does not give a lot of support to the user if they were to
    #   take a mis-step. Consider creating an object that could report better
    #   errors when an incorrect sub-key has been specified.
    results = OhaiMash.new( raw_code_object_results )

    results
  end

  def expand_attribute(attribute)
    expanded = {}
    last_key, *root_keys = attribute.split('/').reverse
    last_key_ptr = root_keys.reverse.reduce(expanded) { |h,k| h[k] = {} ; h[k] }
    [ expanded, last_key_ptr, last_key ]
  end

  def deep_merge(h1, h2)
    h1.merge(h2) { |k,v1,v2| deep_merge(v1, v2) }
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