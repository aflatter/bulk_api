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

  end

end

__END__

  class Resourcee

    attr_reader :request
    delegate :session, :to => :request
    delegate :resource_class, :to => "self.class"
    @@resources = []

    class << self
      attr_writer :application_resource_class
      attr_reader :abstract
      alias_method :abstract?, :abstract

      def resource_class(klass = nil)
        @resource_class = klass if klass
        @resource_class
      end

      def resource_name(name = nil)
        @resource_name = name if name
        @resource_name
      end

      def resources(*resources)
        @@resources = resources unless resources.blank?
        @@resources
      end

      def application_resource_class
        @application_resource_class ||= "ApplicationResource"
        @application_resource_class.is_a?(Class) ? @application_resource_class : Object.const_get(@application_resource_class.to_sym)
      end

      def inherited(base)
        if base.name == application_resource_class.to_s
          base.abstract!
        elsif base.name =~ /(.*)Resource$/
          base.resource_name($1.underscore.pluralize)
        end
      end

      %w/get create update delete/.each do |method|
        define_method(method) do |request|
          handle_response(method, request)
        end
      end

      def abstract!
        @abstract = true
        @@resources = []
      end
      protected :abstract!

      private

      ## TODO: refactor this to some kind of Response class
      #def handle_response(method, request)
      #  response = {}
      #  application_resource = application_resource_class.new(request, :abstract => true)

      #  if application_resource.respond_to?(:authenticate)
      #    raise AuthenticationError unless application_resource.authenticate(method)
      #  end

      #  if application_resource.respond_to?(:authorize)
      #    raise AuthorizationError unless application_resource.authorize(method)
      #  end

      #  # FIXME: Params should be handled nicely
      #  request.params.with_indifferent_access.each do |resource, hash|
      #    next unless resources.blank? || resources.include?(resource.to_sym)
      #    resource_object = instantiate_resource_class(request, resource)
      #    next unless resource_object
      #    collection = resource_object.send(method, hash)
      #    as_json_options = resource_object.send(:as_json_options, resource_object.send(:klass))
      #    options = {:only_ids => (method == 'delete'), :as_json_options => as_json_options}
      #    response.deep_merge! collection.to_hash(resource_object.resource_name.to_sym, options)
      #  end

      #  { :json => response }
      #rescue AuthenticationError
      #  { :status => 401, :json => {} }
      #rescue AuthorizationError
      #  { :status => 403, :json => {} }
      #end

      def instantiate_resource_class(request, resource)
        begin
          "#{resource.to_s.singularize}_resource".classify.constantize.new(request)
        rescue NameError
          begin
            application_resource_class.new(request, :resource_name => resource)
          rescue NameError
          end
        end
      end
    end

    def initialize(request, options = {})
      @request = request
      @resource_name = options[:resource_name].to_s if options[:resource_name]

      # try to get klass to raise error early if something is not ok
      klass unless options[:abstract]
    end

    def get(ids = 'all')
      ids = ids.to_s == 'all' ? nil : ids
      collection = Collection.new
      with_records_auth :get, collection, ids do
        records = if block_given?
          yield ids
        else
          ids ? klass.where(:id => ids) : klass.all
        end
        records.each do |r|
          with_record_auth :get, collection, r.id, r do
            collection.set(r.id, r)
          end
        end
      end
      collection
    end

    def create(hashes)
      collection = Collection.new
      ids = hashes.map { |r| r[:_local_id] }
      with_records_auth :create, collection, ids do
        hashes.each do |attrs|
          local_id = attrs.delete(:_local_id)
          record = klass.new(filter_params(attrs))
          record[:_local_id] = local_id
          yield record if block_given?
          with_record_auth :create, collection, local_id, record do
            record.save
            set_with_validity_check(collection, local_id, record)
          end
        end
      end
      collection
    end

    def update(hashes)
      collection = Collection.new
      ids = hashes.map { |r| r[:id] }
      with_records_auth :update, collection, ids do
        hashes.each do |attrs|
          attrs.delete(:_local_id)
          record = klass.where(:id => attrs[:id]).first
          record.attributes = filter_params(attrs)
          yield record if block_given?
          with_record_auth :update, collection, record.id, record do
            record.save
            set_with_validity_check(collection, record.id, record)
          end
        end
      end
      collection
    end

    def delete(ids)
      collection = Collection.new
      with_records_auth :delete, collection, ids do
        ids.each do |id|
          record = klass.find(id)
          yield record if block_given?
          with_record_auth :delete, collection, record.id, record do
            record.destroy
            set_with_validity_check(collection, record.id, record)
          end
        end
      end
      collection
    end

    def resource_name
      @resource_name || self.class.resource_name
    end

    # def as_json_options(klass)
    #   {}
    # end

    private



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
      filter = send("params_#{type}", klass)
      filter = filter ? filter[resource_name.to_sym] : nil

      if filter
        attributes.delete_if do |k, v|
          delete_if = filter.include?(k)
          type == :accessible ? !delete_if : delete_if
        end
      end

      attributes
    end

    def klass
      @_klass ||= begin
        resource_class || (resource_name ? resource_name.to_s.singularize.classify.constantize : nil) ||
          raise("Could not get resource class, please either set resource_class or resource_name that matches model that you want to use")
      rescue NameError
        raise NameError.new("Could not find class matching your resource_name (#{resource_name} - we were looking for #{resource_name.classify})")
      end
    end
  end
end
