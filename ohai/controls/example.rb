# encoding: utf-8
# copyright: 2018, The Authors

describe ohai do
  its('uptime_seconds') { should be > 360 }
  its('os') { should eq 'darwin' }

end

describe ohai do
  # NOTE: If you stick with the inspec.json parsed solution this is what you 
  #   live with when traversing elements in the results. I don't care for it much
  # its( %w[chef_packages chef version ]) { should eq('14.11.21') }
  its('chef_packages.chef.version') { should eq '14.11.21' }
end