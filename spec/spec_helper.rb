require 'rubygems'
require 'bundler/setup'
Bundler.require(:development)

require 'logger'

$TESTING=true
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'redis/semaphore'
