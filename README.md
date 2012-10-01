redis-semaphore
===============

Implements a mutex and semaphore using Redis and the neat BLPOP command.

The mutex and semaphore is blocking, not polling, and has a fair queue serving processes on a first-come, first-serve basis.

For more info see [Wikipedia](http://en.wikipedia.org/wiki/Semaphore_(programming\)).

Usage
-----

First let's see how to create a mutex:

```ruby
s = Redis::Semaphore.new(:semaphore_name, :connection => "localhost")
s.lock do
  # We're now in a mutex protected area
  # No matter how many processes are running this program,
  # there will be only one running this code block at a time.
  do_something_speshiul()
end
```

While our application is inside the code block given to ```s.lock```, other calls to use the mutex with the same name will block until our code block is finished. Once our mutex unlocks, the next process will unblock and be able to execute the code block. The blocking processes get unblocked in order of arrival, creating a fair queue.

You can also allow a set number of processes inside the semaphore-protected block:

```ruby
s = Redis::Semaphore.new(:semaphore_name, 5, :connection => "localhost")
s.lock do
  # Up to five processes at a time will be able to get inside this code
  # block simultaneously.
  do_something_less_speshiul()
end
```

You don't need to use code blocks, you can also use linear code:

```ruby
s = Redis::Semaphore.new(:semaphore_name, :connection => "localhost")
s.lock
do_something_speshiul()
s.unlock  # Don't forget this, or the mutex will be locked forever!
```

If you don't want to wait forever until the mutex or semaphore release, you can use a timeout, in seconds:

```ruby
if s.lock(5) # This will only block for at most 5 seconds if the mutex stays locked.
  do_something_speshiul()
  s.unlock
else
  puts "Aborted."
end
```

You can check if the mutex or semaphore already exists, or how many resources are left in the semaphore:

```ruby
puts "Someone already initialized this mutex or semaphore!" if s.exists?
puts "There are #{s.available} resources available right now."
```

In the constructor you can pass in any arguments that you would pass to a regular Redis constructor. You can even pass in your custom Redis client:

```ruby
r = Redis.new(:connection => "localhost", :db => 222)
s = Redis::Semaphore.new(:another_name, r)
#...
```

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


Installation
------------

    $ gem install redis-semaphore

Testing
-------

    $ bundle install
    $ rake

Changelog
---------

###0.1.5 October 1, 2012
- Add detection of Redis::Namespace definition to avoid potential bug (thanks ruud!).

###0.1.4 October 1, 2012
- Fixed empty namespaces (thanks ruurd!).

###0.1.3 July 9, 2012
- Tokens are now identifiable (thanks timgaleckas!).

###0.1.2 June 1, 2012
- Add redis-namespace support (thanks neovintage!).

### 0.1.1 September 17, 2011
- When an exception is raised during locked period, ensure it unlocks.

### 0.1.0 August 4, 2011
- Initial release.

Author
------

[David Verhasselt](http://davidverhasselt.com) - david@crowdway.com

Contributors
------------

Thanks to these awesome fellas for their contributions:

- (Rimas Silkaitis)[https://github.com/neovintage]
- (Tim Galeckas)[https://github.com/timgaleckas]
- (Ruurd Pels)[https://github.com/ruurd]
