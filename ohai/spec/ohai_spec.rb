require 'spec_helper'

describe_inspec_resource 'ohai' do

  after(:each) do
    # NOTE: Because the OhaiResource caches the last run in memory it needs to be
    #   reset between each of these runs to ensure that new data will be populated
    OhaiResource.results(nil)
  end

  context 'when no path is provided' do
    context 'when ohai is not on the path' do
      it 'fails with error' do
        environment do
          command('which ohai').returns(stdout: '')
        end

        expect { resource.os }.to raise_error('Ohai Not Found')
      end
    end
    
    context 'when ohai is on the path' do
      context 'when the command returns correctly formed JSON' do
        it 'the top-level keys are defined as methods' do
          environment do
            command('which ohai').returns(stdout: '/path/to/ohai')
            command('/path/to/ohai').returns(stdout: '{ "os": "mac_os_x" }')
          end
  
          expect(resource.os).to eq('mac_os_x')
        end

        it 'the lower-level keys can be reached via chain invocation' do
          environment do
            command('which ohai').returns(stdout: '/path/to/ohai')
            command('/path/to/ohai').returns(stdout: '{ "cpu": { "cores": 4 } }')
          end

          expect(resource.cpu.cores).to eq(4)
        end
      end

      context 'when the command returns incorrectly formed JSON' do
        it 'fails with error' do
          environment do
            command('which ohai').returns(stdout: '/path/to/ohai')
            command('/path/to/ohai').returns(stdout: 'Usage: /path/to/ohai (options)')
          end
  
          expect { resource.os }.to raise_error(JSON::ParserError)
        end

      end
    end
  end
  
  describe 'when a path is provided' do
    context 'when ohai is not on the path'
    context 'when ohai is on the path'
  end
end