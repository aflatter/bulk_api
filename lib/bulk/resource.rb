require 'active_support/hash_with_indifferent_access'
require 'active_support/core_ext/class/attribute'

module Bulk
  class AuthenticationError < StandardError; end
  class AuthorizationError < StandardError; end

  class Resource

    class_attribute :_model_class

    # Pluralized resource name, e.g. tasks.
    attr_reader :resource_name, :request

    class << self
      def model_class(klass = nil)
        return self._model_class unless klass
        self._model_class = klass
      end
    end

    def initialize(request, resource_name = nil)
      @request = request
      @resource_name = resource_name
    end

    def model_class
      return self._model_class if self._model_class

      if resource_name
        model_class = begin
          resource_name.singularize.camelize.constantize 
        rescue NameError
          nil
        end

        return model_class if model_class
      end
      
      raise "Could not determine model class from resource name. Please set 'model_class Foo' in your resource definition."

      # TODO: Try to determine model class from resource class name.
      # self._model_class || self.class.name.gsub(/Resource$/, '').constantize
    end

    def get(ids = 'all')
      ids = ids.to_s == 'all' ? nil : ids
      collection = Collection.new
      with_records_auth :get, collection, ids do
        records = if block_given?
          yield ids
        else
          ids ? model_class.where(:id => ids) : model_class.all
        end
        records.each do |r|
          with_record_auth :get, collection, r.id, r do
            collection.set(r.id, r)
          end
        end
      end

      collection.to_hash(resource_name, :as_json_options => as_json_options(model_class.to_s))
    end

    def create(hashes)
      collection = Collection.new
      ids = hashes.map { |r| r[:_local_id] }
      with_records_auth :create, collection, ids do
        hashes.each do |attrs|
          local_id = attrs.delete(:_local_id)
          record = model_class.new(filter_params(attrs))
          record[:_local_id] = local_id
          yield record if block_given?
          with_record_auth :create, collection, local_id, record do
            record.save
            set_with_validity_check(collection, local_id, record)
          end
        end
      end
      collection.to_hash(resource_name, :as_json_options => as_json_options(model_class.to_s))
    end

    def update(hashes)
      collection = Collection.new
      ids = hashes.map { |r| r[:id] }
      with_records_auth :update, collection, ids do
        hashes.each do |attrs|
          attrs.delete(:_local_id)
          record = model_class.where(:id => attrs[:id]).first
          record.attributes = filter_params(attrs)
          yield record if block_given?
          with_record_auth :update, collection, record.id, record do
            record.save
            set_with_validity_check(collection, record.id, record)
          end
        end
      end
      collection.to_hash(resource_name, :as_json_options => as_json_options(model_class.to_s))
    end

    def delete(ids)
      collection = Collection.new
      with_records_auth :delete, collection, ids do
        ids.each do |id|
          record = model_class.where(:id => id).first

          # Skip records that can not be found.
          next unless record

          yield record if block_given?
          with_record_auth :delete, collection, record.id, record do
            record.destroy
            set_with_validity_check(collection, record.id, record)
          end
        end
      end
      collection.to_hash(
        resource_name,
        :as_json_options => as_json_options(model_class.to_s), 
        :only_ids => true
      )
    end

    protected
 
    def with_record_auth(action, collection, id, record)
      if authorize_record(action, record)
        yield
      else
        collection.errors.set(id, 'forbidden')
      end
    end

    def with_records_auth(action, collection, ids)
      if authorize_records(action, model_class)
        yield
      else
        ids.each do |id|
          collection.errors.set(id, 'forbidden')
        end
      end
    end

    def set_with_validity_check(collection, id, record)
      collection.set(id, record)
      unless record.errors.empty?
        collection.errors.set(id, :invalid, record.errors.to_hash)
      end
    end

    def filter_params(attributes)
      if self.respond_to?(:params_accessible)
        filter_params_for(:accessible, attributes)
      elsif self.respond_to?(:params_protected)
        filter_params_for(:protected, attributes)
      else
        attributes
      end
    end

    def filter_params_for(type, attributes)
      filter = send("params_#{type}", model_class)
      filter = filter ? filter[resource_name.to_sym] : nil

      if filter
        attributes.delete_if do |k, v|
          delete_if = filter.include?(k)
          type == :accessible ? !delete_if : delete_if
        end
      end

      attributes
    end

    # This method will be run on every action for every record that is
    # requested. Override it to implement your own authorization logic.
    # @param [Symbol] action
    # @param [Object] record
    # @return [true,false] whether authorization was successful
    def authorize_record(action, record)
      true
    end

    # This method will run once on every action. Override it to implement
    # collection-level authorization logic.
    # @param [Symbol] action
    # @param [Class]  model class
    # @return [true,false] whether authorization was successful
    def authorize_records(action, model_class)
      true
    end

    # TODO: Not sure if we need that, belongs to the model IMHO.
    def as_json_options(klass)
      {}
    end

  end # Resource

end # Bulk
