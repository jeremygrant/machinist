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
      attributes.each {|key, value| assign_value(key, value) }
    end

    # Undef a couple of methods that are common ActiveRecord attributes.
    # (Both of these are deprecated in Ruby 1.8 anyway.)
    undef_method :id
    undef_method :type

    attr_reader :object

    def method_missing(symbol, *args, &block)
      if cached_attribute?(symbol) # return value from the object if it's cached
        @object.send(symbol)
      else # assign value to the object if it's new
        assign_value(symbol, evaluate_value(symbol, *args, &block))
      end
    end

  private
    def cached_attributes
      @cached_attributes ||= []
    end

    def cached_attribute?(key)
      cached_attributes.include?(key)
    end

    def add_attribute_to_cache(key)
      cached_attributes << key.to_sym
    end

    def assign_value(key, value)
      add_attribute_to_cache(key)
      @object.send("#{key}=", value)
    end

    def evaluate_value(symbol, *args, &block)
      if block
        block.call
      elsif args.first.is_a?(Hash) || args.empty?
        association_class(symbol).make(args.first || {})
      else
        args.first
      end
    end

    def association_class(symbol)
      object.class.reflections[symbol].klass
    end
  end
end

class ActiveRecord::Base
  include Machinist::ActiveRecordExtensions
end