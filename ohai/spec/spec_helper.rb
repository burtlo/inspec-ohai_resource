require 'inspec'
require 'rspec/its'
require 'pry'
require './libraries/ohai'


RSpec.configure do |config|
  #
  # Add a convienent name for the example group to the RSpec lexicon. This
  # allows a user to write:
  #     describe_inspec_resource 'ohai'
  #
  # As opposed to appending a type to the declaration of the spec:
  #     describe 'ohai', type: :inspec_resource'
  #
  config.alias_example_group_to :describe_inspec_resource, type: :inspec_resource
end

shared_context 'InSpec Resources', type: :inspec_resource do
  # Using the subject or described_class does not work. With strings I think that the 
  #   described class is not set. With symbols or constants it may work. When there are strings
  #   the subject value gets set to the last description. This asks for the description at the
  #   top of the entire test. If that is set correctly then the rest will work.
  let(:resource_name) { self.class.top_level_description }
  # Find the resource in the registry based on the resource_name. The resource classes
  #   stored here are not exactly instances of the Resource class (e.g. OhaiResource). They are
  #   instead wrapped with the backend transport mechanism which they will be executed against.
  let(:resource_class) { Inspec::Resource.registry[resource_name] }

  def self.backend_builder(builder = nil)
    if builder
      @backend_builder = builder
    else
      @backend_builder
    end
  end

  def self.environment(&block)
    self.backend_builder(DoubleBuilder.new(&block))
    
    let(:backend) do
      # iterate through all of the backend builders and evaluate them all within
      # the current scope (self). The result of evaluating a backend is a ready-to-go
      # backend. Which should be passed from builder to build so that it builds a more
      # complete picture of the environment.
      
      backend_builders = self.class.parent_groups.map { |parent| parent.backend_builder }.compact
      starting_double = RSpec::Mocks::Double.new('backend')
      backend_builders.inject(starting_double) { |backend, builder| builder.evaluate(self, backend) }
    end
  end

  # Create an instance of the resource with the mock backend and the resource name
  def resource(*args)
    resource_class.new(backend, resource_name, *args)
  end

  let(:subject) { resource }

  # This is a no-op backend that should be overridden. Below is a helper method #environment which
  #   provides some shortcuts for hiding some of the RSpec mocking/stubbing double language.
  def backend
    double(
      <<~BACKEND
        A mocked underlying backend has not been defined. This can be done through the environment
        helper method. Which enables you to specify how the mock envrionment will behave to all requests.

            environment do
              command('which ohai').returns(stdout: '/path/to/ohai')
              command('/path/to/ohai').returns(stdout: '{ "os": "mac_os_x" }')
            end
      BACKEND
    )
  end

end

# This class serves only to create a context to enable a new domain-specific-language (DSL)
#   for defining a backend in a simple way. The DoubleBuilder is constructed with the current 
#   test context which it later defines the #backend method that returns the test double that
#   is built with this DSL.
class DoubleBuilder
  def initialize(&block)
    @content_block = block
  end

  def evaluate(test_context, backend)
    # Evaluate the block provided to queue up a bunch of backend double definitions.
    instance_exec(&@content_block)

    backend_doubles = self.backend_doubles
    test_context.instance_exec do
      # require 'pry' ; binding.pry
      # With all the backend double definitions defined, create a backend to append all these doubles
      backend_doubles.each do |backend_double|
        if backend_double.has_inputs?
          allow(backend).to receive(backend_double.name).with(*backend_double.inputs).and_return(backend_double.outputs)
        else
          allow(backend).to receive(backend_double.name).with(no_args).and_return(backend_double.outputs)
        end
      end
    end

    backend
  end

  # Store all the doubling specified in the initial part of #evaluate
  def backend_doubles
    @backend_doubles ||= []
  end
  
  def method_missing(backend_method_name, *args, &block)
    backend_double = BackendDouble.new(backend_method_name)
    backend_double.inputs = args unless args.empty?
    backend_doubles.push backend_double
    # NOTE: The block is ignored.
    self
  end

  # When defining a new aspect of the environment (e.g. command, file)
  # you will often want a result from that detail. Because of the fluent
  # interface this double builder provides this is a way to grab the last
  # build double and append a mock of a return object.
  #
  # @TODO this shouldn't be used without a double being created, an
  #   error will be generated with that last_double coming back as a nil.
  #   There may be some interesting behavior that could be undertaken
  #   here when no aspect is provided. It may also be better to throw a
  #   useful exception that describes use.
  def returns(method_signature_as_hash)
    return_result = Hashie::Mash.new(method_signature_as_hash)
    last_double = backend_doubles.last
    results_double_name = "#{last_double.name}_#{last_double.inputs}_RESULTS"
    last_double.outputs = RSpec::Mocks::Double.new(results_double_name,return_result)
    self
  end

  # Create a object to hold the backend doubling information
  class BackendDouble
    class NoInputsSpecifed ; end

    def initialize(name)
      @name = name
      @inputs = NoInputsSpecifed
    end

    def has_inputs?
      inputs != NoInputsSpecifed
    end

    attr_accessor :name, :inputs, :outputs
  end  
  
end
