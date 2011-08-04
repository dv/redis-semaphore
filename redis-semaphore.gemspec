Gem::Specification.new do |s|
  s.name        = 'redis-semaphore'
  s.version     = '0.1.0'
  s.date        = Time.now.strftime('%Y-%m%-d') 
  s.summary     = 'Implements a distributed semaphore or mutex using Redis.'
  s.authors     = ['David Verhasselt']
  s.email       = 'david@crowdway.com'
  s.homepage    = 'http://github.com/dv/redis-semaphore'
  s.has_rdoc    = false

  s.files       = []
  s.files      += Dir.glob("lib/**/*")

  s.add_dependency  'redis'

  s.description = <<description
Implements a distributed semaphore or mutex using Redis.
description
end
