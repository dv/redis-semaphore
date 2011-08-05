require File.dirname(__FILE__) + '/spec_helper'

describe "redis" do
  before(:all) do
    # use database 15 for testing so we dont accidentally step on you real data
    @redis = Redis.new :db => 15
    @semaphore = Redis::Semaphore.new(:my_semaphore, @redis)
  end

  before(:each) do
    @redis.flushdb
  end

  after(:each) do
    @redis.flushdb
  end

  after(:all) do
    @redis.quit
  end
  
  it "should be unlocked from the start" do
    @semaphore.locked?.should == false
  end
  
  it "should lock and unlock" do
    @semaphore.lock
    @semaphore.locked?.should == true
    @semaphore.unlock
    @semaphore.locked?.should == false
  end
  
  it "should not lock twice as a mutex" do
    @semaphore.lock
    @semaphore.lock(1).should == false
  end
  
  it "should not lock three times when only two available" do
    multisem = Redis::Semaphore.new(:my_semaphore2, 2, @redis)
    multisem.lock.should == true
    multisem.lock(1).should == true
    multisem.lock(1).should == false
  end
  
  it "should execute the given code block" do
    code_executed = false
    @semaphore.lock do
      code_executed = true
    end
    code_executed.should == true    
  end
  
end