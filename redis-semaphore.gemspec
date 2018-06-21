Gem::Specification.new do |s|
  s.name        = 'redis-semaphore'
  s.version     = '0.3.2'
  s.summary     = 'Implements a distributed semaphore or mutex using Redis.'
  s.authors     = ['David Verhasselt']
  s.email       = 'david@crowdway.com'
  s.homepage    = 'http://github.com/dv/redis-semaphore'
  s.license     = 'MIT'

  files         = %w(README.md Rakefile LICENSE)
  files        += Dir.glob("lib/**/*")
  files        += Dir.glob("spec/**/*")
  s.files       = files

  s.add_dependency 'redis'
  s.add_development_dependency 'rake', '< 11'
  s.add_development_dependency 'rspec', '>= 2.14'
  s.add_development_dependency 'timecop'
  s.add_development_dependency 'pry'

  s.description = <<description
Implements a distributed semaphore or mutex using Redis.
description
end
