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
      @use_local_time = opts.delete(:use_local_time)
      @tokens = []
    end

    def exists_or_create!
      token = @redis.getset(exists_key, API_VERSION)

      if token.nil?
        create!
      elsif token != API_VERSION
        raise "Semaphore exists but running as wrong version (version #{token} vs #{API_VERSION})."
      else
        true
      end
    end

    def available_count
      @redis.llen(available_key)
    end

    def delete!
      @redis.del(available_key)
      @redis.del(grabbed_key)
      @redis.del(exists_key)
    end

    def lock(timeout = 0)
      exists_or_create!
      release_stale_locks! if check_staleness?

      token_pair = @redis.blpop(available_key, timeout)
      return false if token_pair.nil?

      current_token = token_pair[1]
      @tokens.push(current_token)
      @redis.hset(grabbed_key, current_token, current_time.to_f)
      return_value = current_token

      if block_given?
        begin
          return_value = yield current_token
        ensure
          signal(current_token)
        end
      end

      return_value
    end
    alias_method :wait, :lock

    def unlock
      return false unless locked?
      signal(@tokens.pop)[1]
    end

    def locked?(token = nil)
      if token
        @redis.hexists(grabbed_key, token)
      else
        @tokens.each do |token|
          return true if locked?(token)
        end
        
        false
      end
    end

    def signal(token = 1)
      token ||= generate_unique_token

      @redis.multi do
        @redis.hdel grabbed_key, token
        @redis.lpush available_key, token
      end
    end

    def exists?
      @redis.exists(exists_key)
    end

    def all_tokens
      @redis.multi do
        @redis.lrange(available_key, 0, -1)
        @redis.hkeys(grabbed_key)
      end.flatten
    end

    def generate_unique_token
      tokens = all_tokens
      token = Random.rand.to_s

      while(tokens.include? token)
        token = Random.rand.to_s
      end
    end

    def release_stale_locks!
      simple_mutex(:release_locks, 10) do
        @redis.hgetall(grabbed_key).each do |token, locked_at|
          timed_out_at = locked_at.to_f + @stale_client_timeout

          if timed_out_at < current_time.to_f
            signal(token)
          end
        end
      end
    end

  private
    def simple_mutex(key_name, expires = nil)
      key_name = namespaced_key(key_name) if key_name.kind_of? Symbol
      token = @redis.setnx(key_name, API_VERSION)

      return false unless token
      @redis.expire(key_name, expires) unless expires.nil?

      begin
        yield token
      ensure
        @redis.del(key_name)
      end
    end

    def create!
      @redis.expire(exists_key, 10)

      @redis.multi do
        @redis.del(grabbed_key)
        @redis.del(available_key)
        @resource_count.times do |index|
          @redis.rpush(available_key, index)
        end

        # Persist key
        @redis.del(exists_key)
        @redis.set(exists_key, API_VERSION)
      end
    end

    def check_staleness?
      !@stale_client_timeout.nil?
    end

    def redis_namespace?
      (defined?(Redis::Namespace) && @redis.is_a?(Redis::Namespace))
    end

    def namespaced_key(variable)
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

    def current_time
      if @use_local_time
        Time.now
      else
        begin
          instant = @redis.time
          Time.at(instant[0], instant[1])
        rescue
          @use_local_time = true
          current_time
        end
      end
    end
  end
end
