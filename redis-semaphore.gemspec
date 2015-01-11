Gem::Specification.new do |s|
  s.name        = 'redis-semaphore'
  s.version     = '0.2.4'
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
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec', '>= 2.14'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'timecop'

  s.description = <<description
Implements a distributed semaphore or mutex using Redis.
description
end
