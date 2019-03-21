class ElasticSearchConfig < Inspec.resource(1)
name 'elasticsearch_config'

  example <<~EXAMPLE
    describe elasticsearch_config('a.yml') do
      its('xpack.security.authc.realms.pki1.type') { should eq('pki') }
      its(%w[xpack security authc realms pki1 type]) { should eq('pki') }
    end
  EXAMPLE
  
  def deep_merge(h1, h2)
    h1.merge(h2) { |k,v1,v2| deep_merge(v1, v2) }
  end

  def expand_key(key, value)
    final_hash = {}
    hash = final_hash
    
    keys = key.split(".")
    keys.each_with_index do |sub_key, index|
      hash[sub_key] = {} unless hash.has_key?(sub_key)
      if index == keys.length - 1
        if value.is_a?(Hash)
          value.each do |value_sub_key_value|
            hash[sub_key] = deep_merge(hash[sub_key],expand_key(*value_sub_key_value))
          end
        else
          hash[sub_key] = value
        end
      else
        hash = hash[sub_key]
      end
    end

    final_hash
  end

  def self.define_methods_for(names)
    names.each do |name|
      define_method name.to_sym do
        instance_variable_get("@config")[name.to_s]
      end
    end
  end

  class ElasticConfigMash < Hashie::Mash
    disable_warnings
  end

  def initialize(config_path)
    # TODO: if the config can be defined in different formats then the file extension should be checked    
    results = inspec.yaml(config_path).to_h
    
    expanded_results = {}
    # NOTE: Look at every key and if that key has a dot notation 
    #   it means there is more heirachy to add that was shortened up
    results.each do |key, value|
      expanded_results = deep_merge(expanded_results,expand_key(key, value))s
    end

    @config = ElasticConfigMash.new(expanded_results)
    ElasticSearchConfig.define_methods_for(expanded_results.keys)
  end
end