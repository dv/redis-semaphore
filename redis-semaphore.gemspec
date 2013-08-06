Gem::Specification.new do |s|
  s.name        = 'redis-semaphore'
  s.version     = '0.2.1'
  s.summary     = 'Implements a distributed semaphore or mutex using Redis.'
  s.authors     = ['David Verhasselt']
  s.email       = 'david@crowdway.com'
  s.homepage    = 'http://github.com/dv/redis-semaphore'

  files         = %w(README.md Rakefile LICENSE)
  files        += Dir.glob("lib/**/*")
  files        += Dir.glob("spec/**/*")
  s.files       = files

  s.add_dependency  'redis'

  s.description = <<description
Implements a distributed semaphore or mutex using Redis.
description
end
