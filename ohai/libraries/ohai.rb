class OhaiResource < Inspec.resource(1)
  name 'ohai'

  example <<~EXAMPLE
    describe ohai do
      its('uptime_seconds') { should be > 360 }
    end
    
    describe ohai(attribute: 'os') do
      its('os').os { should eq 'darwin' }
    end

    describe ohai(attribute: 'chef_packages/chef/version') do
      its('chef_packages.chef.version') { should eq '14.18.11' }
    end

    describe ohai(attribute: [ 'os', 'chef_packages/chef/version' ]) do
      its('os') { should eq 'darwin' }
      its('chef_packages.chef.version') { should eq '14.18.11' }
    end

    describe ohai(directory: '/etc/chef/ohai_plugins') do
      # ...
    end

    describe ohai(directory: [ '/etc/chef/ohai_plugins', '/tmp/ohai_plugins' ]) do
      # ...
    end
    
    describe ohai('/my/path/to/ohai') do
      its('chef_packages.chef.version') { should eq '14.18.11' }
    end

    describe ohai(path: '/my/path/to/ohai', attribute: [ 'os', 'chef_packages' ]) do
      its('os') { should eq 'darwin' }
      its('chef_packages.chef.version') { should eq '14.18.11' }
    end
  EXAMPLE

  # When the resource is created you have a few options:
  #
  #   * no argument will default to finding ohai and run it as-is
  #   * the path to ohai and run it as-is
  #   * the path and various options passed to it
  #
  def initialize(ohai_path_or_options = {})
    options = if ohai_path_or_options.is_a?(String)
      { path: ohai_path_or_options }
    else
      ohai_path_or_options
    end

    verify_options!(options)
    
    options[:attribute] = Array(options[:attribute] || options['attribute'])
    options[:directory] = Array(options[:directory] || options['directory'])

    @options = Hashie::Mash.new(options)
  end

  def version
    inspec.command("#{ohai_path} --version").stdout.strip.split(' ').last
  end

  def raw_data
    @raw_data ||= load_results
  end

  attr_reader :options

  private

  def supported_options
    %w[ path attribute directory ].map { |opt| [ opt , opt.to_sym ] }.flatten
  end

  def verify_options!(options)
    unsupported_options = options.keys.find_all { |key| ! supported_options.include?(key) }

    unless unsupported_options.empty?
      raise InvalidResourceOptions.new(self, supported_options, unsupported_options)
    end
  end

  class InvalidResourceOptions < StandardError
    def initialize(resource, supported_options, given_options)
      @resource = resource
      @supported_options = supported_options
      @given_options = given_options
    end

    attr_reader :resource, :supported_options, :given_options

    def message
      error_message = <<~RAISE
        Ohai resource does not support options: #{ unsupported_options.join(', ') }
        Supported Options: #{ supported_options.map { |opt| opt.inspect }.join(', ') }
      RAISE
    end
  end

  def method_missing(name,*args,&block)
    if raw_data
      if raw_data.key?(name)
        raw_data[name]
      else
        raise InvalidAttribute.new(self, name)
      end
    else
      super
    end
  end

  class InvalidAttribute < StandardError
    def initialize(resource, attribute_name)
      @resource = resource
      @attribute_name = attribute_name
    end

    attr_reader :resource, :attribute_name
  
    def message
      <<~RAISE
        #{resource} results did not contain the attribute: #{attribute_name}
        Supported attributes: #{resource.raw_data.keys.join(', ')}
      RAISE
    end
  end

  def ohai_path
    @ohai_path ||= begin
      path = options[:path] || find_ohai_path_on_target
      if path.nil? || path.empty?
        raise PathCouldNotBeFound.new(self,options[:path],find_ohai_path_on_target)
      end
      path
    end
  end

  class PathCouldNotBeFound < StandardError
    def initialize(resource, provided_path, derived_path)
      @resource = resource
      @provided_path = nil_or_empty_default_to(provided_path, '<NONE>')
      @derived_path = nil_or_empty_default_to(derived_path, '<NONE>')
    end

    attr_reader :resource, :provided_path, :derived_path

    def message
      <<~RAISE
        #{resource} could not be found
        Provided Path: #{provided_path}
         Derived Path: #{derived_path}
      RAISE
    end

    private

    def nil_or_empty_default_to(value,default_to)
      (value.nil? || value.empty?) ? default_to : value
    end
  end

  def find_ohai_path_on_target
    # TODO: provide support for all platforms and other strageties
    inspec.command('which ohai').stdout.chomp
  end

  def build_ohai_command
    cmd = "#{ohai_path}"

    options[:directory].each do |dir|
      cmd += " --directory #{dir}"
    end

    options[:attribute].each do |attribute|
      cmd += " #{attribute}"
    end

    cmd
  end

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

  class ResultsParsingError < RuntimeError
    def initialize(resource, results, parse_error)
      @resource = resource
      @results = results
      @parse_error = parse_error
    end

    attr_reader :resource, :results, :parse_error

    def message
      <<~RAISE
        #{resource} failed to parse the results:
          ERROR: [#{parse_error.class}] #{parse_error} 

        RESULTS: #{results}

      RAISE
    end
  end
  # Run the ohai command provided at the path, process the results and cache the data for
  # future resources to use.
  # 
  # @param path the path to the ohai executable when invoked will generate the JSON results
  # @return the
  def load_results
    result = inspec.command(build_ohai_command).result
    raise ExecutionFailure.new(self, build_ohai_command, result) if result.exit_status != 0
    
    partitioned_results = partition_results(result.stdout)

    # TODO: A JSON::ParserError is thrown here when the JSON is incorrect but the resulting error
    #   message does not inclue a lot of information to make it easy to find out what is going on
    #   so it may be important to make a new error that shows the command executed. The resulting
    #   standard out and then display the error. It would also be nice if inspec provided a place
    #   locally when this error message is so big.
    parsed_results = partitioned_results.map do |result|
      begin
        JSON.parse(result)
      rescue JSON::ParserError => parse_error
        raise ResultsParsingError.new(self, result, parse_error)
      end
    end

    raw_code_object_results = if options[:attribute].empty?
      parsed_results.first
    else
      attribute_with_results = options[:attribute].each_with_index.map do |attribute, index|
        matching_results = parsed_results[index]
        matching_results = Array(matching_results).first if Array(matching_results).count == 1
        
        # The attribute itself may be a compounded key separated by forward-slashes.
        # So we need to build a hash and have a pointer to the root,
        # the last hash and the final key to be added
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
    root = {}
    last_key, *root_keys = attribute.split('/').reverse
    last_hash = root_keys.reverse.reduce(root) { |h,k| h[k] = {} ; h[k] }
    [ root, last_hash, last_key ]
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

  class ExecutionFailure < RuntimeError
    def initialize(resource, command, result)
      @resource = resource
      @command = command
      @result = result
    end

    attr_reader :resource, :command, :result

    def message
      <<~RAISE
        #{resource} failed to execute.
        Command: #{command}
        Results:
          EXIT STATUS: #{result.exit_status}

               STDOUT: #{nil_or_empty_default_to(result.stdout,'<NONE>')}

               STDERR: #{nil_or_empty_default_to(result.stderr,'<NONE>')}

      RAISE
    end

    private

    def nil_or_empty_default_to(value,default_to)
      (value.nil? || value.empty?) ? default_to : value
    end
  end
end