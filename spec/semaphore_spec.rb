require File.dirname(__FILE__) + '/spec_helper'

describe "redis" do
  before(:all) do
    # use database 15 for testing so we dont accidentally step on your real data
    @redis = Redis.new :db => 15
  end

  before(:each) do
    @redis.flushdb
  end

  after(:all) do
    @redis.quit
  end

  shared_examples_for "a semaphore" do

    it "has the correct amount of available resources" do
      semaphore.lock
      expect(semaphore.unlock).to eq(1)
      expect(semaphore.available_count).to eq(1)
    end

    it "has the correct amount of available resources before locking" do
      expect(semaphore.available_count).to eq(1)
    end

    it "should not exist from the start" do
      expect(semaphore.exists?).to eq(false)
      semaphore.lock
      expect(semaphore.exists?).to eq(true)
    end

    it "should be unlocked from the start" do
      expect(semaphore.locked?).to eq(false)
    end

    it "should lock and unlock" do
      semaphore.lock(1)
      expect(semaphore.locked?).to eq(true)
      semaphore.unlock
      expect(semaphore.locked?).to eq(false)
    end

    it "should not lock twice as a mutex" do
      expect(semaphore.lock(1)).not_to eq(false)
      expect(semaphore.lock(1)).to eq(false)
    end

    it "should not lock three times when only two available" do
      expect(multisem.lock(1)).not_to eq(false)
      expect(multisem.lock(1)).not_to eq(false)
      expect(multisem.lock(1)).to eq(false)
    end

    it "should always have the correct lock-status" do
      multisem.lock(1)
      multisem.lock(1)

      expect(multisem.locked?).to eq(true)
      multisem.unlock
      expect(multisem.locked?).to eq(true)
      multisem.unlock
      expect(multisem.locked?).to eq(false)
    end

    it "should get all different tokens when saturating" do
      ids = []
      2.times do
        ids << multisem.lock(1)
      end

      expect(ids).to eq(%w(0 1))
    end

    it "should execute the given code block" do
      code_executed = false
      semaphore.lock(1) do
        code_executed = true
      end
      expect(code_executed).to eq(true)
    end

    it "should pass an exception right through" do
      expect {
        semaphore.lock(1) do
          raise Exception, "redis semaphore exception"
        end
      }.to raise_error(Exception, "redis semaphore exception")
    end

    it "should not leave the semaphore locked after raising an exception" do
      expect {
        semaphore.lock(1) do
          raise Exception, "redis semaphore exception"
        end
      }.to raise_error(Exception, "redis semaphore exception")

      expect(semaphore.locked?).to eq(false)
    end

    it "should return the value of the block if block-style locking is used" do
      block_value = semaphore.lock(1) do
        42
      end
      expect(block_value).to eq(42)
    end

    it "can return the passed in token to replicate old behaviour" do
      lock_token = semaphore.lock(1)
      semaphore.unlock()

      block_value = semaphore.lock(1) do |token|
        token
      end
      expect(block_value).to eq(lock_token)
    end

    it "should disappear without a trace when calling `delete!`" do
      original_key_size = @redis.keys.count

      semaphore.exists_or_create!
      semaphore.delete!

      expect(@redis.keys.count).to eq(original_key_size)
    end

    it "should not block when the timeout is zero" do
      did_we_get_in = false

      semaphore.lock do
        semaphore.lock(0) do
          did_we_get_in = true
        end
      end

      expect(did_we_get_in).to be false
    end

    it "should be locked when the timeout is zero" do
      semaphore.lock(0) do
        expect(semaphore.locked?).to be true
      end
    end

    it "should recover after being killed after lpop of AVAILABLE" do
      semaphore.lock
      semaphore.unlock

      expect(semaphore.available_count). to eq(1)

      @redis.lpop(semaphore.send(:available_key))

      semaphore.lock(-1)

      expect(semaphore.locked?).to be true
    end
  end

  describe "semaphore with expiration" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis, :expiration => 2) }
    let(:multisem) { Redis::Semaphore.new(:my_semaphore_2, :resources => 2, :redis => @redis, :expiration => 2) }

    it_behaves_like "a semaphore"

    it "expires keys" do
      original_key_size = @redis.keys.count
      semaphore.exists_or_create!
      sleep 3.0
      expect(@redis.keys.count).to eq(original_key_size)
    end

    it "expires keys after unlocking" do
      original_key_size = @redis.keys.count
      semaphore.lock do
        # noop
      end
      sleep 3.0
      expect(@redis.keys.count).to eq(original_key_size)
    end
  end

  describe "semaphore without staleness checking" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis) }
    let(:multisem) { Redis::Semaphore.new(:my_semaphore_2, :resources => 2, :redis => @redis) }

    it_behaves_like "a semaphore"

    it "can dynamically add resources" do
      semaphore.exists_or_create!

      3.times do
        semaphore.signal
      end

      expect(semaphore.available_count).to eq(4)

      semaphore.wait(1)
      semaphore.wait(1)
      semaphore.wait(1)

      expect(semaphore.available_count).to eq(1)
    end

    it "can have stale locks released by a third process" do
      watchdog = Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 1)
      semaphore.lock

      sleep 0.5

      watchdog.release_stale_locks!
      expect(semaphore.locked?).to eq(true)

      sleep 0.6

      watchdog.release_stale_locks!
      expect(semaphore.locked?).to eq(false)
    end
  end

  describe "semaphore with staleness checking" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 5) }
    let(:multisem) { Redis::Semaphore.new(:my_semaphore_2, :resources => 2, :redis => @redis, :stale_client_timeout => 5) }

    it_behaves_like "a semaphore"

    it "should restore resources of stale clients" do
      hyper_aggressive_sem = Redis::Semaphore.new(:hyper_aggressive_sem, :resources => 1, :redis => @redis, :stale_client_timeout => 1)

      expect(hyper_aggressive_sem.lock(1)).not_to eq(false)
      expect(hyper_aggressive_sem.lock(1)).to eq(false)
      expect(hyper_aggressive_sem.lock(1)).not_to eq(false)
    end
  end

  describe "redis time" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 5) }

    before(:all) do
      Timecop.freeze(Time.local(1990))
    end

    it "with time support should return a different time than frozen time" do
      expect(semaphore.send(:current_time)).not_to eq(Time.now)
    end

    it "with use_local_time should return the same time as frozen time" do
      semaphore = Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 5, :use_local_time => true)
      expect(semaphore.send(:current_time)).to eq(Time.now)
    end

    it "without time support should return the same time as frozen time" do
      expect(@redis).to receive(:time).and_raise(Redis::CommandError)
      expect(semaphore.send(:current_time)).to eq(Time.now)
    end
  end

  describe "all_tokens" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis, :stale_client_timeout => 5) }

    it "includes tokens from available and grabbed keys" do
      semaphore.exists_or_create!
      available_keys = semaphore.all_tokens
      semaphore.lock(1)
      grabbed_keys = semaphore.all_tokens

      expect(available_keys).to eq(grabbed_keys)
    end
  end

  describe "version" do
    context "with an existing versionless semaphore" do
      let(:old_sem) { Redis::Semaphore.new(:my_semaphore, :redis => @redis) }
      let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis) }
      let(:version_key) { old_sem.send(:version_key) }

      before do
        old_sem.exists_or_create!
        @redis.del(version_key)
      end

      it "sets the version key" do
        semaphore.exists_or_create!
        expect(@redis.get(version_key)).not_to be_nil
      end
    end
  end

  # Private method tests, do not use
  describe "simple_expiring_mutex" do
    let(:semaphore) { Redis::Semaphore.new(:my_semaphore, :redis => @redis) }

    before do
      semaphore.class.send(:public, :simple_expiring_mutex)
    end

    it "gracefully expires stale lock" do
      expiration = 1

      thread =
        Thread.new do
          semaphore.simple_expiring_mutex(:test, expiration) do
            sleep 3
          end
        end

      sleep 1.5

      expect(semaphore.simple_expiring_mutex(:test, expiration)).to be_falsy

      sleep expiration

      it_worked = false
      semaphore.simple_expiring_mutex(:test, expiration) do
        it_worked = true
      end

      expect(it_worked).to be_truthy
      thread.join
    end
  end
end
