require 'redis'

class Redis
  class Semaphore

    attr_reader :resources
    #stale_client_timeout is the threshold of time before we assume
    #that something has gone terribly wrong with a client and we
    #invalidate it's lock.
    #Default is nil for which we don't check for stale clients
    attr_accessor :stale_client_timeout

    # RedisSempahore.new(:my_semaphore, 5, myRedis)
    # RedisSemaphore.new(:my_semaphore, myRedis)
    # RedisSemaphore.new(:my_semaphore, :connection => "", :port => "")
    # RedisSemaphore.new(:my_semaphore, :path => "bla")
    def initialize(*args)
      raise "Need at least two arguments" if args.size < 2

      @locked = false
      @name = args.shift.to_s
      @redis = args.pop
      if !(@redis.is_a?(Redis) || (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace)))
        @redis = Redis.new(@redis)
      end
      @resources = args.pop || 1
    end

    def available
      @redis.llen(list_name)
    end

    def exists?
      @redis.type(exists_name) == 'list'
    end

    def delete!
      @redis.del(list_name)
      @redis.del(exists_name)
    end

    def lock(timeout = 0)
      exists_or_create!

      resource_index = @redis.blpop(list_name, timeout)
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
        @redis.lpush(list_name, @locked)
        @redis.hdel grabbed_name, @locked
      end
      @locked = false
    end

    def locked?
      !!@locked
    end


  private
    def list_name
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace)) ? "#{@name}:LIST" : "SEMAPHORE:#{@name}:LIST"
    end

    def exists_name
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace)) ? "#{@name}:EXISTS" : "SEMAPHORE:#{@name}:EXISTS"
    end

    def grabbed_name
      "SEMAPHORE::#{@name}::GRABBED"
    end

    def exists_or_create!
      if exists?
        if stale_client_timeout
          #fix missing clients
          @redis.hgetall(grabbed_name).each do |resource_index, last_held_at|
            if (last_held_at.to_i + stale_client_timeout) < DateTime.now.strftime('%s').to_i
              @redis.multi do
                @redis.hdel(grabbed_name, resource_index)
                #in case of race condition, remove the resource that the other process added
                @redis.lrem(list_name, 0, resource_index)
                @redis.lpush(list_name, resource_index)
              end
            end
          end
        end
      else
        @redis.multi do
          @redis.del(list_name)
          @redis.del(exists_name)
          @resources.times do |index|
            @redis.rpush(list_name, index)
            @redis.rpush(exists_name, index)
          end
        end
      end
    end
  end
end
