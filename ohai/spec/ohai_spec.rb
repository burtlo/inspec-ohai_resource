require 'spec_helper'

describe_inspec_resource 'ohai' do

  context 'relying on the automatic path' do
    environment do
      command('which ohai').returns(stdout: '/path/to/ohai')
      command('/path/to/ohai --version').returns(stdout: "Ohai: 14.8.10\n")
    end

    its(:version) { should eq '14.8.10' }

    it 'has a version' do
      expect(resource.version).to eq('14.8.10')
    end

    context 'with no parameters' do
      context 'top-level attributes' do
        environment do
          command('/path/to/ohai').returns(result: {
            stdout: '{ "os": "darwin" }', exit_status: 0
          })
        end

        it 'are accessible via dot-notation' do
          expect(resource.os).to eq('darwin')
        end
      end

      context 'nested attributes' do
        environment do
          command('/path/to/ohai').returns(result: {
            stdout: '{ "cpu": { "cores": 4 } }', exit_status: 0 
          })
        end

        it 'are accessible via dot-notation' do
          expect(resource.cpu.cores).to eq(4)
        end
      end
    end

    context 'with an attribute parameter' do
      # Specifying an attribute as a parameter focuses the ohai run to only
      # that attribute. This makes ohai run quicker as it ignores all other
      # attributes.
      
        # NOTE: Because of the way the environment helper works a let helper will not work:
        # 
        # let(:chef_packages_stdout) do
        #   <<~STDOUT
        #     {
        #      ...
        #     }
        #   STDOUT
        # end
      environment do
        chef_packages_stdout = <<~STDOUT
          {
            "chef": {
              "version": "14.11.21",
              "chef_root": "/Users/.../chef-14.11.21/lib"
            },
            "ohai": {
              "version": "14.8.10",
              "ohai_root": "/Users/.../ohai-14.8.10/lib/ohai"
            }
          }
        STDOUT
        command('/path/to/ohai chef_packages').returns(result: {
          stdout: chef_packages_stdout, exit_status: 0
        })
      end

      it 'the attribute is accessible via dot-notation' do
        # NOTE: Initially I thought that when specifying an attribute the interface of the resource
        #   should change so that the attribute name would not have to be repeated. But you can
        #   specify multiple attributes and to support that would potentially lead to collisions
        #   or surprises with the data that is returned.
        expect(resource(attribute: 'chef_packages').chef_packages.chef.version).to eq('14.11.21')
      end

      context 'defined as a path to the specific attribute' do
        environment do
          chef_packages_ohai_stdout = <<~STDOUT
            {
              "version": "14.8.10",
              "ohai_root": "/Users/.../ohai-14.8.10/lib/ohai"
            }
          STDOUT
          command('/path/to/ohai chef_packages/ohai').returns(result: {
            stdout: chef_packages_ohai_stdout, exit_status: 0
          })
        end

        it 'is accessible via dot-notation' do
          expect(resource(attribute: 'chef_packages/ohai').chef_packages.ohai.version).to eq('14.8.10')
        end
      end

      context 'that returns a singular result represented by an array' do
        # When asking for an attribute that results in only the values
        # then the results come back in an Array format.
        environment do
          command('/path/to/ohai os').returns(result: {
            stdout: '[ "darwin" ]', exit_status: 0
          })
        end

        it 'is accessible via dot-notation' do
          # NOTE: Initially I thought that when specifying an attribute the interface of the resource
          #   should change so that the attribute name would not have to be repeated. But you can
          #   specify multiple attributes and to support that would potentially lead to collisions
          #   or surprises with the data that is returned.
          expect(resource(attribute: 'os').os).to eq('darwin')
        end
      end
    end

    context 'with mulitple attribute parameters' do
      # When you provide multiple attributes as parameters ohai will 
      # return multiple JSON objects next each other in the output. This
      # requires that the output be correctly partitioned and then assigned
      # back to the parameter that was provided
      environment do
        ohai_stdout = <<~STDOUT
          [
            "darwin"
          ]
          {
            "chef": {
              "version": "14.11.21",
              "chef_root": "/Users/.../chef-14.11.21/lib"
            },
            "ohai": {
              "version": "14.8.10",
              "ohai_root": "/Users/.../ohai-14.8.10/lib/ohai"
            }
          }
        STDOUT
        command('/path/to/ohai os chef_packages').returns(result: {
          stdout: ohai_stdout, exit_status: 0
        })
      end
      
      it 'two attributes are accessible via dot-notation' do
        # NOTE: Initially I thought that when specifying an attribute the interface of the resource
        #   should change so that the attribute name would not have to be repeated. But you can
        #   specify multiple attributes and to support that would potentially lead to collisions
        #   or surprises with the data that is returned.
        expect(resource(attribute: ['os', 'chef_packages']).os).to eq('darwin')
        expect(resource(attribute: ['os', 'chef_packages']).chef_packages.chef.version).to eq('14.11.21')
      end

      context 'in the same tree' do
        # The concern here is that because the data coming back share similar keys
        # that the data would truncate one another instead of merging together properly
        environment do
          two_chef_package_attributes_stdout = <<~STDOUT
            {
              "version": "14.11.21",
              "chef_root": "/Users/.../chef-14.11.21/lib"
            }
            {
              "version": "14.8.10",
              "ohai_root": "/Users/.../ohai-14.8.10/lib/ohai"
            }
          STDOUT
          command('/path/to/ohai chef_packages/chef chef_packages/ohai').returns(result: {
            stdout: two_chef_package_attributes_stdout, exit_status: 0
          })
        end

        it 'is accessible via dot-notation' do
          result = resource(attribute: ['chef_packages/chef', 'chef_packages/ohai'])
          expect(result.chef_packages.chef.version).to eq('14.11.21')
          expect(result.chef_packages.ohai.version).to eq('14.8.10')
        end
      end
    end

    context 'with a directory parameter' do
      # The directory parameter is a location where additional plugins
      # will be loaded. This should be passed to the ohai command. The
      # results should be the same.
      environment do
        command('/path/to/ohai --directory plugin_dir').returns(result: {
          stdout: '{ "os": "darwin" }', exit_status: 0
        })
      end

      it 'is specified in the command' do
        expect(resource(directory: 'plugin_dir').os).to eq('darwin')
      end
    end

    context 'with multiple directory parameters' do
      environment do
        command('/path/to/ohai --directory plugin_dir1 --directory plugin_dir2').returns(result: {
          stdout: '{ "os": "darwin" }', exit_status: 0
        })
      end

      it 'is specified in the command' do
        expect(resource(directory: ['plugin_dir1', 'plugin_dir2']).os).to eq('darwin')
      end
    end

    context 'when the command returns incorrectly formed JSON' do
      environment do
        command('/path/to/ohai').returns(result: {
          stdout: 'Usage: /path/to/ohai (options)', exit_status: 0
        })
      end

      it 'fails with error' do        
        expect { resource.os }.to raise_error(OhaiResource::ResultsParsingError)
      end
    end
  end

  context 'relying on an automatic path' do
    context 'but ohai is not found' do
      environment do
        command('which ohai').returns(stdout: '')
      end

      it 'fails with error' do        
        expect { resource.os }.to raise_error(OhaiResource::PathCouldNotBeFound)
      end
    end
  end
  
  context 'when a valid path is provided' do
    environment do
      command('/another/path/to/ohai').returns(result: {
        stdout: '{ "os": "darwin" }', exit_status: 0
      })
    end

    it 'the top-level keys are defined as methods' do
      expect(resource(ohai_bin_path: '/another/path/to/ohai').os).to eq('darwin')
    end
  end

  context 'when an invalid path is provided' do
    environment do
      command('my-ohai').returns(result: {
        stdout: '', exit_status: 1
      })
    end

    it 'fails with error' do
      expect { resource('my-ohai').os }.to raise_error(OhaiResource::ExecutionFailure)
    end
  end

  context 'when an invalid option is provided' do
    it 'fails with error' do
      expect { resource(animal: 'zebra') }.to raise_error(OhaiResource::InvalidResourceOptions)
    end
  end

  context 'when an invalid attribute is retrieved' do
    environment do
      command('which ohai').returns(stdout: '/path/to/ohai')
      command('/path/to/ohai').returns(result: {
        stdout: '{ "os": "darwin" }', exit_status: 0
      })
    end

    it 'fails with error' do
      expect { resource.unknown }.to raise_error(OhaiResource::InvalidAttribute)
    end
  end
end