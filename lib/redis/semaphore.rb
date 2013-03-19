require 'redis'

class Redis
  class Semaphore
    API_VERSION = "1"

    #stale_client_timeout is the threshold of time before we assume
    #that something has gone terribly wrong with a client and we
    #invalidate it's lock.
    # Default is nil for which we don't check for stale clients
    # Redis::Semaphore.new(:my_semaphore, :stale_client_timeout => 30, :redis => myRedis)
    # Redis::Semaphore.new(:my_semaphore, :redis => myRedis)
    # Redis::Semaphore.new(:my_semaphore, :resources => 1, :redis => myRedis)
    # Redis::Semaphore.new(:my_semaphore, :connection => "", :port => "")
    # Redis::Semaphore.new(:my_semaphore, :path => "bla")
    def initialize(name, opts = {})
      @name = name
      @resource_count = opts.delete(:resources) || 1
      @stale_client_timeout = opts.delete(:stale_client_timeout)
      @redis = opts.delete(:redis) || Redis.new(opts)
    end

    def available
      @redis.llen(available_key)
    end

    def delete!
      @redis.del(available_key)
      @redis.del(grabbed_key)
      @redis.del(exists_key)
    end

    def lock(timeout = 0, &block)
      exists_or_create!
      release_stale_locks! if check_staleness?

      @token = @redis.blpop(available_name, timeout)
      return false if @token.nil?

      @token = token[1]
      @redis.hset(grabbed_name, @token, Time.now.to_i)
      
      if block_given?
        begin
          yield @token
        ensure
          signal(@token)
        end
      end

      @token
    end
    alias_method :wait, :lock

    def unlock
      return false unless locked?
      signal(@token)
    end

    def locked?(token = nil)
      if token
        @redis.hexists(grabbed_name, token)
      else
        if @token
          if check_staleness
            locked?(@token)
          else
            true
          end
        end
      end
    end

    def signal(token = 1)
      @redis.multi do
        @redis.hdel grabbed_name, token
        @redis.lpush available_name, token
      end
    end

  private
    def simple_mutex(key_name, expires = nil)
      version = @redis.getset(key_name, API_VERSION)

      return false unless version.nil?
      @redis.expire(key_name, expires) unless expires.nil?

      begin
        yield version
      ensure
        @redis.del(key_name)
      end
    end

    def release_stale_locks!
      simple_mutex(release_locks_key, 10) do
        @redis.hgetall(grabbed_key).each do |token, locked_at|
          timed_out_at = locked_at.to_i + @stale_client_timeout

          if timed_out_at < Time.now.to_i
            signal(token)
          end
        end
      end
    end

    def create!
      @redis.expire(exists_key, 10)

      @redis.multi do
        @redis.del(grabbed_key)
        @redis.del(available_key)
        @resources.times do |index|
          @redis.rpush(available_key, index)
        end
        @redis.del(exists_key)
        @redis.set(exists_key, API_VERSION)
      end
    end

    def exists_or_create!
      version = @redis.getset(exists_name, API_VERSION)

      if version.nil?
        create!
      elsif version != API_VERSION
        raise "Semaphore exists but running as wrong version (version #{version} vs #{API_VERSION})."
      else
        true
      end
    end

    def check_staleness?
      !@stale_client_timeout.nil?
    end

    def redis_namespace?
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace))
    end

    def namespaced_key_name(variable)
      if redis_namespace?
        "#{@name}:#{variable}"
      else
        "SEMAPHORE:#{@name}:#{variable}"
      end
    end

    def available_key
      @available_key ||= namespaced_key('AVAILABLE')
    end

    def exists_key
      @exists_key ||= namespaced_key('EXISTS')
    end

    def grabbed_key
      @grabbed_key ||= namespaced_key('GRABBED')
    end
  end
end
