class OhaiResource < Inspec.resource(1)
  name 'ohai'

  example <<~EXAMPLE
    describe ohai do
      its('uptime_seconds') { should be > 360 }
    end
  EXAMPLE
  
  # NOTE: If you call this method without a param then return the existing results,
  #   if there are any. If you pass a param you are using this as a setter method
  #   so assign to the results and then return that.
  def self.results(new_results = nil)
    if new_results
      @results = new_results

      # To provide a top-level interface on the resource within the test files the keys
      #  at the top of the results that came back need to define methods on the instance.
      new_results.keys.each do |key|
        define_method key do
          ohai_results[key]
        end
      end
    end
    
    @results
  end

  
  def initialize(ohai_path_override = nil)
    # NOTE: A specific path to the binary could be provided
    # NOTE: Other options could also be provided to pass along to the execution
    # NOTE: Plugins and plugin paths could also be specifed as an option on creation
    #   because not running all the plugins would make for a faster executing resource
    
    # NOTE: This is not platform agnostic and requires ohai to be on the path
    #     ohai_path = inspec.command('which ohai').stdout.chomp
    #
    # NOTE: When the command is not found the resulting ohai_path would be empty
    #   a decision should be made to make that know to the user and how to fail 
    #   the resource.
    
    # NOTE: Next, with the path to Ohai you could invoke the command multiple times:
    #   
    #     @ohai_results = inspec.command(ohai_path).stdout
    # 
    #   Each resource would run the command and produce the results.

    # NOTE: To get around the performance issue you could have to introduce some caching
    #   mechanism and generally I think it is safe to cache in this case one run for the 
    #   lifetime of this inspec exec ...

    # NOTE: Store the resulting run in the class object and retrieve it from there if it 
    #   it is already present. Otherwise this is the first time and its time to go get it.
    @ohai_results = OhaiResource.results || load_results_from(ohai_path(ohai_path_override))
  end

  def ohai_path(ohai_path_override = nil)
    ohai_path_override || inspec.command('which ohai').stdout.chomp
  end

  # NOTE: Creating a subclass of the Hashie::Mash because that is the only place
  #   in which it is safe for you to disable warnings when the data structure steps on methods
  #   that are important to Hashie::Mash. Because this data is going to be read-only I think
  #   its alright if we disable the warnings.
  class OhaiMash < Hashie::Mash
    # NOTE: In the results `counters` and `kernel` contain some keys: drop, index and size
    disable_warnings
  end

  def load_results_from(path)
    # NOTE: You could use this to create the JSON object. But I don't like interacting with it this way
    # results = inspec.json({ content: inspec.command(ohai_path).stdout })

    # SEE: https://www.youtube.com/watch?v=9rbb2RWa9Oo&index=10&list=PL11cZfNdwNyMHrqIo7aLWq9Wy3y63Nspt
    results_in_json = JSON.parse(inspec.command(ohai_path).stdout)
    
    results = OhaiMash.new( results_in_json )
    OhaiResource.results(results)
    results
  end

  attr_reader :ohai_results
end