require 'rack'
require 'active_support/core_ext/class/attribute'

module Bulk

  class Application

    class_attribute :_resources

    class << self

      # Helper to allow nicer resource definition syntax.
      def resources(*names)
        return self._resources if names.empty?
        self._resources = names
      end

    end

    def call(env)
      request  = Request.new(self, env)

      # Return error if we can not map the request method to an action.
      unless action = request.action
        # Method not allowed.
        # FIXME: Return JSON-encoded error.
        return [405, {'Content-Type' => 'application/json'}, []]
      end

      # Return error if we can not authenticate the request.
      unless before_request(request)
        # FIXME: Return JSON-encoded error.
        return [401, {'Content-Type' => 'application/json'}, []]
      end

      dispatch(action, request)
    end

    def resources
      self._resources
    end

    protected

    # Dispatches an action to the requested resources.
    #
    # @param [Symbol] action
    # @param [Bulk::Request] request
    def dispatch(action, request)
      result = Hash.new; response = Rack::Response.new

      request.resources.each do |name, more|
        resource = resource_for(name)
        next unless resource
        result.deep_merge! resource.new(request, name).send(action, more)
      end

      response['Content-Type'] = 'application/json'
      response.write(result.to_json)
      response.finish
    end

    # Determines the class that should be used to handle this resource.
    # Falls back to application resource If it can not map the name to a class,
    #
    # @return [Bulk::Resource]
    def resource_for(name)
      begin
        "#{name}_resource".camelize.constantize
      rescue NameError
        application_resource
      end
    end

    # Returns the application resource if defined or simply Bulk::Resource
    # otherwise. Override this method if you have more than one API endpoint.
    # @return [Bulk::Resource]
    def application_resource
      defined?(ApplicationResource) ? ApplicationResource : Bulk::Resource
    end

    # Override this method if you want to authenticate a request first.
    # @return [true,false]
    def before_request(request)
      true
    end

  end # Application

end # Bulk
