#!/usr/bin/env ruby
# encoding: utf-8

class EatWhatDict

  attr_reader :foods
  attr_reader :ops

  @foods = []
  @ops = []

  def initialize
    @foods = []
    @ops = []
  end

  def foods=(val)
puts "dict here!"
    @foods = val.uniq
  end

  def ops=(val)
    @ops = val.uniq
  end
  
end
