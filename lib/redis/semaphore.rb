require 'redis'

class Redis
  class Semaphore
    
    attr_reader :resources
    
    # RedisSempahore.new(:my_semaphore, 5, myRedis)
    # RedisSemaphore.new(:my_semaphore, myRedis)
    # RedisSemaphore.new(:my_semaphore, :connection => "", :port => "")
    # RedisSemaphore.new(:my_semaphore, :path => "bla")
    def initialize(*args)
      raise "Need at least two arguments" if args.size < 2
      
      @locked = false
      @name = args.shift.to_s
      @redis = args.pop
      @redis = Redis.new(@redis) unless @redis.kind_of? Redis
      @resources = args.pop || 1
      
    end
    
    def available
      @redis.llen(list_name)
    end
    
    def exists?
      @redis.exists(exists_name)
    end
    
    def delete!
      @redis.del(list_name)
      @redis.del(exists_name)
    end
    
    def lock(timeout = 0)
      exists_or_create!
      
      return false if @redis.blpop(list_name, timeout).nil?
      
      @locked = true
      if block_given?
        yield
        unlock
      end
      
      true
    end
    
    def unlock
      return false unless locked?
      
      @redis.rpush(list_name, 1)
      @locked = false
    end
    
    def locked?
      @locked
    end
    
    
  private  
    def list_name
      "SEMAPHORE::#{@name}::LIST"
    end
    
    def exists_name
      "SEMAPHORE::#{@name}::EXISTS"
    end
    
    def exists_or_create!
      exists = @redis.getset(exists_name, 1)
      
      if "1" != exists
        @resources.times do
          @redis.lpush(list_name, 1)
        end
      end
    end
    
  end
end
