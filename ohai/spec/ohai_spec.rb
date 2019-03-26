require 'spec_helper'

describe_inspec_resource 'ohai' do

  context 'relying on the automatic path' do
    it 'has a version' do
      environment do
        command('which ohai').returns(stdout: '/path/to/ohai')
        command('/path/to/ohai --version').returns(stdout: "Ohai: 14.8.10\n")
      end

      expect(resource.version).to eq('14.8.10')
    end

    context 'with no parameters' do
      it 'attributes are accessible via dot-notation' do
        environment do
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai').returns(result: {
            stdout: '{ "os": "darwin" }', exit_status: 0
          })
        end

        expect(resource.os).to eq('darwin')
      end

      it 'nested attributes are accessible via dot-notation' do
        environment do
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai').returns(result: {
            stdout: '{ "cpu": { "cores": 4 } }', exit_status: 0 
          })
        end

        expect(resource.cpu.cores).to eq(4)
      end
    end

    context 'with an attribute parameter' do
      it 'singular result attributes are accessible via dot-notation' do
        environment do
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai os').returns(result: {
            stdout: '[ "darwin" ]', exit_status: 0
          })
        end

        # NOTE: Should this be changed to be #value? because it seems strange to
        #   say the os attribute and then repeat os afterwards
        expect(resource(attribute: 'os').os).to eq('darwin')
      end

      # NOTE: Because of the way that environment works this let helper is not found:
      # 
      # let(:chef_packages_stdout) do
      #   <<~STDOUT
      #     {
      #       "chef": {
      #         "version": "14.11.21",
      #         "chef_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/chef-14.11.21/lib"
      #       },
      #       "ohai": {
      #         "version": "14.8.10",
      #         "ohai_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/ohai-14.8.10/lib/ohai"
      #       }
      #     }
      #   STDOUT
      # end

      it 'attributes are accessible via dot-notation' do
        environment do
          chef_packages_stdout = <<~STDOUT
            {
              "chef": {
                "version": "14.11.21",
                "chef_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/chef-14.11.21/lib"
              },
              "ohai": {
                "version": "14.8.10",
                "ohai_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/ohai-14.8.10/lib/ohai"
              }
            }
          STDOUT
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai chef_packages').returns(result: {
            stdout: chef_packages_stdout, exit_status: 0
          })
        end

        # NOTE: Should this be changed so that #chef_packages does not need to be defined?
        expect(resource(attribute: 'chef_packages').chef_packages.chef.version).to eq('14.11.21')
      end


      it 'two attributes are accessible via dot-notation' do
        environment do
          ohai_stdout = <<~STDOUT
            [
              "darwin"
            ]
            {
              "chef": {
                "version": "14.11.21",
                "chef_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/chef-14.11.21/lib"
              },
              "ohai": {
                "version": "14.8.10",
                "ohai_root": "/Users/franklinwebber/.rbenv/versions/2.4.3/lib/ruby/gems/2.4.0/gems/ohai-14.8.10/lib/ohai"
              }
            }
          STDOUT
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai os chef_packages').returns(result: {
            stdout: ohai_stdout, exit_status: 0
          })
        end

        expect(resource(attribute: ['os', 'chef_packages']).os).to eq('darwin')
        expect(resource(attribute: ['os', 'chef_packages']).chef_packages.chef.version).to eq('14.11.21')
      end
    end

    context 'but ohai is not found' do
      it 'fails with error' do
        environment do
          command('which ohai').returns(stdout: '')
        end

        expect { resource.os }.to raise_error('Ohai Not Found')
      end
    end

    context 'when the command returns incorrectly formed JSON' do
      it 'fails with error' do
        environment do
          command('which ohai').returns(stdout: '/path/to/ohai')
          command('/path/to/ohai').returns(result: {
            stdout: 'Usage: /path/to/ohai (options)', exit_status: 0
          })
        end

        expect { resource.os }.to raise_error(JSON::ParserError)
      end
    end
  end
  
  context 'when a valid path is provided' do
    it 'the top-level keys are defined as methods' do
      environment do
        command('which ohai').returns(stdout: '/path/to/ohai')
        command('/path/to/ohai').returns(result: {
          stdout: '{ "os": "darwin" }', exit_status: 0
        })
      end

      expect(resource.os).to eq('darwin')
    end
  end

  context 'when an invalid path is provided' do
    it 'fails with error' do
      environment do
        command('my-ohai').returns(result: {
          stdout: '', exit_status: 1
        })
      end
      expect { resource('my-ohai').os }.to raise_error('Ohai my-ohai failed to execute (1)')
    end
  end
end