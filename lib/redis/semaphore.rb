require 'redis'

class Redis
  class InconsistentStateError < StandardError
  end

  class Semaphore

    #stale_client_timeout is the threshold of time before we assume
    #that something has gone terribly wrong with a client and we
    #invalidate it's lock.
    #Default is nil for which we don't check for stale clients
    # RedisSemaphore.new(:my_semaphore, :stale_client_timeout => 30, :redis => myRedis)
    # RedisSempahore.new(:my_semaphore, :redis => myRedis)
    # RedisSemaphore.new(:my_semaphore, :resources => 1, :redis => myRedis)
    # RedisSemaphore.new(:my_semaphore, :connection => "", :port => "")
    # RedisSemaphore.new(:my_semaphore, :path => "bla")
    def initialize(name, opts={})
      @locked = false
      @name = name
      @resources = opts.delete(:resources)
      @resources ||= 1
      @stale_client_timeout = opts.delete(:stale_client_timeout)
      @redis = opts.delete(:redis)
      @redis ||= Redis.new(opts)
    end

    def available
      @redis.llen(available_name)
    end

    def delete!
      @redis.del(available_name)
      @redis.del(grabbed_name)
      @redis.del(exists_name)
    end

    def lock(timeout = 0)
      exists_or_create!

      resource_index = @redis.blpop(available_name, timeout)
      return false if resource_index.nil?
      @locked = resource_index[1].to_i
      @redis.hset grabbed_name, @locked, DateTime.now.strftime('%s')

      if block_given?
        begin
          yield @locked
        ensure
          unlock
        end
      end

      true
    end

    def unlock
      return false unless locked?

      @redis.multi do
        @redis.lpush(available_name, @locked)
        @redis.hdel grabbed_name, @locked
      end
      @locked = false
    end

    def locked?
      !!@locked
    end


  private
    def available_name
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace)) ? "#{@name}:AVAILABLE" : "SEMAPHORE:#{@name}:AVAILABLE"
    end

    def exists_name
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace)) ? "#{@name}:EXISTS" : "SEMAPHORE:#{@name}:EXISTS"
    end

    def grabbed_name
      "SEMAPHORE::#{@name}::GRABBED"
    end

    def exists_or_create!
      old = @redis.get(exists_name)
      raise InconsistentStateError.new('Code does not match data') if old && old.to_i != @resources
      if @redis.getset(exists_name, @resources)
        if @stale_client_timeout
          #fix missing clients
          @redis.hgetall(grabbed_name).each do |resource_index, last_held_at|
            if (last_held_at.to_i + @stale_client_timeout) < DateTime.now.strftime('%s').to_i
              @redis.multi do
                @redis.hdel(grabbed_name, resource_index)
                #in case of race condition, remove the resource that the other process added
                @redis.lrem(available_name, 0, resource_index)
                @redis.lpush(available_name, resource_index)
              end
            end
          end
        end
      else
        @redis.multi do
          @redis.del(available_name)
          @resources.times do |index|
            @redis.rpush(available_name, index)
          end
        end
      end
    end
  end
end
