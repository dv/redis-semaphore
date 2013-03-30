require File.dirname(__FILE__) + '/spec_helper'

shared_examples_for "a semaphore" do
  before(:all) do
    # use database 15 for testing so we dont accidentally step on you real data
    @redis = Redis.new :db => 15
  end

  before(:each) do
    @redis.flushdb
  end

  after(:all) do
    @redis.quit
  end

  it "should be unlocked from the start" do
    semaphore.locked?.should == false
  end

  it "should lock and unlock" do
    semaphore.lock(1)
    semaphore.locked?.should == true
    semaphore.unlock
    semaphore.locked?.should == false
  end

  it "should not lock twice as a mutex" do
    semaphore.lock(1).should_not == false
    semaphore.lock(1).should == false
  end

  it "should not lock three times when only two available" do
    multisem.lock(1).should_not == false
    multisem.lock(1).should_not == false
    multisem.lock(1).should == false
  end

  it "should always have the correct lock-status" do
    multisem.lock(1)
    multisem.lock(1)

    multisem.locked?.should == true
    multisem.unlock
    multisem.locked?.should == true
    multisem.unlock
    multisem.locked?.should == false
  end

  it "should get all different tokens when saturating" do
    ids = []
    2.times do 
      ids << multisem.lock(1)
    end

    ids.should == %w(0 1)
  end

  it "should execute the given code block" do
    code_executed = false
    semaphore.lock(1) do
      code_executed = true
    end
    code_executed.should == true
  end

  it "should pass an exception right through" do
    lambda do
      semaphore.lock(1) do
        raise Exception, "redis semaphore exception"
      end
    end.should raise_error(Exception, "redis semaphore exception")
  end

  it "should not leave the semaphore locked after raising an exception" do
    lambda do
      semaphore.lock(1) do
        raise Exception
      end
    end.should raise_error

    semaphore.locked?.should == false
  end
end

describe "redis semaphore without staleness checking" do
  let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis) }
  let(:multisem) { Redis::Semaphore.new(:my_semaphore_2, :resources => 2, :redis => @redis) }

  it_behaves_like "a semaphore"
end

describe "redis semaphore with staleness checking" do
  let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 5) }
  let(:multisem) { Redis::Semaphore.new(:my_semaphore_2, :resources => 2, :redis => @redis, :stale_client_timeout => 5) }

  it_behaves_like "a semaphore"

  it "should restore resources of stale clients" do
    hyper_aggressive_sem = Redis::Semaphore.new(:hyper_aggressive_sem, :resources => 1, :redis => @redis, :stale_client_timeout => 1)
    
    hyper_aggressive_sem.lock(1).should_not == false
    hyper_aggressive_sem.lock(1).should == false
    hyper_aggressive_sem.lock(1).should_not == false
  end
end
