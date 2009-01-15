require 'active_support'
require 'active_record'
require 'sham'
 
module Machinist
  def self.with_save_nerfed
    begin
      @@nerfed = true
      yield
    ensure
      @@nerfed = false
    end
  end
  
  @@nerfed = false
  def self.nerfed?
    @@nerfed
  end
  
  module ActiveRecordExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def blueprint(&blueprint)
        @blueprint = blueprint
      end
  
      def make(attributes = {})
        raise "No blueprint for class #{self}" if @blueprint.nil?
        lathe = Lathe.new(self, attributes)
        lathe.instance_eval(&@blueprint)
        unless Machinist.nerfed?
          lathe.object.save!
          lathe.object.reload
        end
        returning(lathe.object) do |object|
          yield object if block_given?
        end
      end
    
      def make_unsaved(attributes = {})
        returning(Machinist.with_save_nerfed { make(attributes) }) do |object|
          yield object if block_given?
        end
      end
    end
  end
  
  class Lathe
    def initialize(klass, attributes = {})
      @object = klass.new
      attributes.each {|key, value| @object.send("#{key}=", value) }
      @assigned_attributes = attributes.keys.map(&:to_sym)
    end

    # Undef a couple of methods that are common ActiveRecord attributes.
    # (Both of these are deprecated in Ruby 1.8 anyway.)
    undef_method :id
    undef_method :type
    
    attr_reader :object

    def method_missing(symbol, *args, &block)
      if @assigned_attributes.include?(symbol)
        @object.send(symbol)
      else
        value = if block && count_attribute?(symbol)
          symbol = strip_count_from_symbol(symbol)
          make_collection_with_count(symbol, block.call)
        elsif block
          block.call
        elsif count_attribute?(symbol)
          symbol = strip_count_from_symbol(symbol)
          make_collection_with_count(symbol, args.first)
        elsif args.first.is_a?(Hash) || args.empty?
          association_class(symbol).make(args.first || {})
        else
          args.first
        end
        @object.send("#{symbol}=", value)
        @assigned_attributes << symbol
      end
    end

  private
    def association_class(symbol)
      object.class.reflections[symbol].klass
    end

    module Format
      COUNT_ATTRIBUTE = /(.*)_count$/
    end

    def count_attribute?(symbol)
      symbol.to_s =~ Format::COUNT_ATTRIBUTE
    end

    def strip_count_from_symbol(symbol)
      (symbol.to_s =~ Format::COUNT_ATTRIBUTE)? $1.to_sym: symbol
    end

    def make_collection_with_count(symbol, count)
      collection_class = association_class(symbol)
      returning(collection = []) do
        count.times do |counter|
          collection << collection_class.make
        end
      end
    end
  end
end

class ActiveRecord::Base
  include Machinist::ActiveRecordExtensions
end

