require 'rubygems'
require 'bundler/setup'
Bundler.require(:development)

$TESTING=true
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'redis/semaphore'
