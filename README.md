[![Code Climate](https://codeclimate.com/github/dv/redis-semaphore.svg?branch=master)](https://codeclimate.com/github/dv/redis-semaphore)
[![Build Status](https://travis-ci.org/dv/redis-semaphore.svg?branch=master)](https://travis-ci.org/dv/redis-semaphore)

redis-semaphore
===============

Implements a mutex and semaphore using Redis and the neat BLPOP command.

The mutex and semaphore is blocking, not polling, and has a fair queue serving processes on a first-come, first-serve basis. It can also have an optional timeout after which a lock is unlocked automatically, to protect against dead clients.

For more info see [Wikipedia](http://en.wikipedia.org/wiki/Semaphore_(programming)).

Important change in v0.3.0
===========================

If you've been using `redis-semaphore` before version `0.3.0` you should be aware that the interface for `lock` has changed slightly. Before `0.3` calling `semaphore.lock(0)` (with `0` as the timeout) would block the semaphore indefinitely, just like a redis `blpop` command would.

This has changed in `0.3` to mean *do not block at all*. You can still omit the argument entirely, or pass in `nil` to get the old functionality back. Examples:

```ruby
# These block indefinitely until a resource becomes available:
semaphore.lock
semaphore.lock(nil)

# This does not block at all and rather returns immediately if there's no
# resource available:
semaphore.lock(0)
```

Usage
-----

Create a mutex:

```ruby
s = Redis::Semaphore.new(:semaphore_name, :host => "localhost")
s.lock do
  # We're now in a mutex protected area
  # No matter how many processes are running this program,
  # there will be only one running this code block at a time.
  work
end
```

While our application is inside the code block given to ```s.lock```, other calls to use the mutex with the same name will block until our code block is finished. Once our mutex unlocks, the next process will unblock and be able to execute the code block. The blocking processes get unblocked in order of arrival, creating a fair queue.

You can also allow a set number of processes inside the semaphore-protected block, in case you have a well-defined number of resources available:

```ruby
s = Redis::Semaphore.new(:semaphore_name, :resources => 5, :host => "localhost")
s.lock do
  # Up to five processes at a time will be able to get inside this code
  # block simultaneously.
  work
end
```

You're not obligated to use code blocks, linear calls work just fine:

```ruby
s = Redis::Semaphore.new(:semaphore_name, :host => "localhost")
s.lock
work
s.unlock  # Don't forget this, or the mutex will stay locked!
```

If you don't want to wait forever until the semaphore releases, you can pass in a timeout of seconds you want to wait:

```ruby
if s.lock(5) # This will only block for at most 5 seconds if the semaphore stays locked.
  work
  s.unlock
else
  puts "Aborted."
end
```

You can check if the mutex or semaphore already exists, or how many resources are left in the semaphore:

```ruby
puts "This semaphore does exist." if s.exists?
puts "There are #{s.available_count} resources available right now."
```

When calling ```unlock```, the new number of available resources is returned:

```ruby
sem.lock
sem.unlock # returns 1
sem.available_count # also returns 1
```

In the constructor you can pass in any arguments that you would pass to a regular Redis constructor. You can even pass in your custom Redis client:

```ruby
r = Redis.new(:host => "localhost", :db => 222)
s = Redis::Semaphore.new(:another_name, :redis => r)
#...
```

Note that it's [a bad idea to reuse the same redis client across threads](https://github.com/dv/redis-semaphore/issues/18), due to the blocking nature of the `blpop` command. We might add support for this in a future version.

If an exception happens during a lock, the lock will automatically be released:

```ruby
begin
  s.lock do
    raise Exception
  end
rescue
  s.locked? # false
end
```


Staleness
---------

To allow for clients to die, and the token returned to the list, a stale-check was added. As soon as a lock is started, the time of the lock is set. If another process detects that the timeout has passed since the lock was set, it can force unlock the lock itself.

There are two ways to take advantage of this. You can either define a :stale\_client\_timeout upon initialization. This will check for stale locks everytime your program wants to lock the semaphore:

```ruby
s = Redis::Semaphore.new(:stale_semaphore, :redis = r, :stale_client_timeout => 5) # in seconds
```

Or you could start a different thread or program that frequently checks for stale locks. This has the advantage of unblocking blocking calls to Semaphore#lock as well:

```ruby
normal_sem = Redis::Semaphore.new(:semaphore, :host => "localhost")

Thread.new do
  watchdog = Redis::Semaphore.new(:semaphore, :host => "localhost", :stale_client_timeout => 5)

  while(true) do
    watchdog.release_stale_locks!
    sleep 1
  end
end

normal_sem.lock
sleep 5
normal_sem.locked? # returns false

normal_sem.lock
normal_sem.lock(5) # will block until the watchdog releases the previous lock after 1 second
```


Advanced
--------

### Wait and Signal

The methods ```wait``` and ```signal```, the traditional method names of a Semaphore, are also implemented. ```wait``` is aliased to lock, while ```signal``` puts the specified token back on the semaphore, or generates a unique new token and puts that back if none is passed:

```ruby
# Retrieve 2 resources
token1 = sem.wait
token2 = sem.wait

work

# Put 3 resources back
sem.signal(token1)
sem.signal(token2)
sem.signal

sem.available_count # returns 3
```

This can be used to create a semaphore where the process that consumes resources, and the process that generates resources, are not the same. An example is a dynamic queue system with a consumer process and a producer process:

```ruby
# Consumer process
job = semaphore.wait

# Producer process
semaphore.signal(new_job) # Job can be any string, it will be passed unmodified to the consumer process
```

Used in this fashion, a timeout does not make sense. Using the :stale\_client\_timeout here is not recommended.


### Use local time

When calculating the timeouts, redis-semaphore uses the Redis TIME command by default, which fetches the time on the Redis server. This is good if you're running distributed semaphores to keep all clients on the same clock, but does incur an extra round-trip for every action that requires the time.

You can add the option ```:use_local_time => true``` during initialization to use the local time of the client instead of the Redis server time, which saves one extra roundtrip. This is good if e.g. you're only running one client.

```ruby
s = Redis::Semaphore.new(:local_semaphore, :redis = r, :stale_client_timeout => 5, :use_local_time => true)
```

Redis servers earlier than version 2.6 don't support the TIME command. In that case we fall back to using the local time automatically.


### Expiration

```redis-semaphore``` supports an expiration option, which will call the **EXPIRE** Redis command on all related keys (except for `grabbed_keys`), to make sure that after a while all evidence of the semaphore will disappear and your Redis server will not be cluttered with unused keys. Pass in the expiration timeout in seconds:

```ruby
s = Redis::Semaphore.new(:local_semaphore, :redis = r, :expiration => 100)
```

This option should only be used if you know what you're doing. If you chose a wrong expiration timeout then the semaphore might disappear in the middle of a critical section. For most situations just using the `delete!` command should suffice to remove all semaphore keys from the server after you're done using the semaphore.

Installation
------------

    $ gem install redis-semaphore

Testing
-------

    $ bundle install
    $ rake

Changelog
---------

###0.3.1 April 17, 2016 (Pending)
- Fix `sem.lock(0)` bug (thanks eugenk!).
- Fix `release_stale_locks!` deadlock bug (thanks mfischer-zd for the bug-report!).

###0.3.0 January 24, 2016
- Change API to include non-blocking option for `#lock` (thanks tomclose!).
- Fix unwanted persisting of `available_key` (thanks dany1468!).
- Fix `available_count` returning 0 for nonexisting semaphores (thanks mikeryz!).

###0.2.4 January 11, 2015
- Fix bug with TIME and redis-namespace (thanks sos4nt!).
- Add expiration option (thanks jcalvert!).
- Update API version logic.

More in [CHANGELOG](CHANGELOG.md).

Contributors
------------

Thanks to these awesome people for their contributions:

- [Rimas Silkaitis](https://github.com/neovintage)
- [Tim Galeckas](https://github.com/timgaleckas)
- [Ruurd Pels](https://github.com/ruurd)
- [Prathan Thananart](https://github.com/scomma)
- [dubdromic](https://github.com/dubdromic)
- [Dmitriy Kiriyenko](https://github.com/dmitriy-kiriyenko)
- [presskey](https://github.com/presskey)
- [Stephen Bussey](https://github.com/sb8244)
- [frobcode](https://github.com/frobcode)
- [Petteri Räty](https://github.com/betelgeuse)
- [Stefan Schüßler](https://github.com/sos4nt)
- [Jonathan Calvert](https://github.com/jcalvert)
- [mikeryz](https://github.com/mikeryz)
- [tomclose](https://github.com/tomclose)
- [Eugen Kuksa](https://github.com/eugenk)
- [Eugene Kenny](https://github.com/eugeneius)

### "Merge"-button clicker

[David Verhasselt](http://davidverhasselt.com) - david@crowdway.com
