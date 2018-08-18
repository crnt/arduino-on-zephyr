#!/usr/bin/ruby

require 'json'
require 'optparse'

open(ARGV[0]) do |f|
  js = JSON.load(f)
  ver = js['toolsDependencies'].select {|t| t['name'] == 'BA2-toolchain'}[0]['version']
  print ver
end
