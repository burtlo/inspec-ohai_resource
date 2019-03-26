# encoding: utf-8
# copyright: 2018, The Authors

describe ohai do
  # NOTE: If you stick with the inspec.json parsed solution this is what you 
  #   live with when traversing elements in the results. I don't care for it much
  # its( %w[chef_packages chef version ]) { should eq('14.11.21') }
  its('chef_packages.chef.version') { should eq '14.11.21' }
end

describe elasticsearch_config('a.yml') do
  its('xpack.security.authc.realms.pki1.type') { should eq('pki') }
  its('xpack.security.authc.realms.pki1.order') { should eq(1) }
end

describe elasticsearch_config('b.yml') do
  its('xpack.security.authc.realms.pki1.type') { should eq('pki') }
  its('xpack.security.authc.realms.pki1.order') { should eq(1) }
end

describe elasticsearch_config('c.yml') do
  its('xpack.security.authc.realms.pki1.type') { should eq('pki') }
  its('xpack.security.authc.realms.pki1.order') { should eq(1) }
end

module Inspec::Resources
  class Directory

    def initialize(path, options = {})
      super path
      @recursive = options[:recursive]
    end
    def files
      # *nix solution
      results = inspec.command("ls -R #{path}").stdout

      files_in_root, *sub_directories = results.split("\n\n")
      files_found = files_in_root.split("\n").map { |f| inspec.file(File.join(file.path,f)) }

      if @recursive
        files_found = sub_directories.map do |sub_dir|
          sub_dir_path, sub_dir_files = sub_dir.split(":\n",2)
          sub_dir_files.split("\n").map { |f| inspec.file(File.join(file.path,sub_dir_path,f)) }
        end.flatten
      end

      files_found
    end
  end
end

# NOTE: This is a potentional interface but ...
# describe directory('ohai') do
#   its('files') { should include('controls') }
# end
# NOTE: the above could be written as ...
describe directory('ohai/controls') do
  it { should exist }
end

# The following could be a reasonable use of the `directory.files`
directory('ohai').files.each do |file|
  describe file do
    it { should_not be_executable }
  end
end

# But how about redefining the file matchers to support an array
RSpec::Matchers.define :be_executable do
  match do |file|
    Array(file).all? { |f| f.executable?(@by, @by_user) }
  end

  chain :by do |by|
    @by = by
  end

  chain :by_user do |by_user|
    @by_user = by_user
  end

  description do
    res = 'be executable'
    res += " by #{@by}" unless @by.nil?
    res += " by user #{@by_user}" unless @by_user.nil?
    res
  end

  failure_message do |actual|
    # NOTE: comma-separation might not be the best separator (formatted on newlines probably)
    failed = Array(actual).reject { |f| f.executable?(@by, @by_user) }.map {|f| f.path }
    "expected: #{failed.join(', ')} to be executable"
  end

  failure_message_when_negated do |actual|
    # NOTE: comma-separation might not be the best separator (formatted on newlines probably)
    failed = Array(actual).find_all { |f| f.executable?(@by, @by_user) }.map {|f| f.path }
    "expected: #{failed.join(', ')} to not be executable"
  end
end

  
describe directory('ohai') do
  its('files') { should_not be_executable }
  its('files') { should be_executable }
end

describe directory('ohai', recursive: true) do
  its('files') { should_not be_executable }
  its('files') { should be_executable }
end

describe file('ohai/inspec.yml') do
  it { should_not be_executable }
  it { should be_executable }
end

# describe directory('ohai', recursive: true).find(/\.md$/) do
#   its('files') { should_not be_executable }
#   its('files') { should be_executable }
# end