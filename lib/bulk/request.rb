require 'active_support/core_ext/hash/slice'
require 'rack/request'

module Bulk

  # This class provides a few convenience methods for incoming requests.
  class Request < Rack::Request

    attr_reader :app

    # @param [Bulk::Application] app
    # @param [Hash] env
    def initialize(app, env)
      super(env)
      @app = app
    end

    # Overridden to use hash with indifferent access.
    # @return [ActiveSupport::HashWithIndifferentAccess] params
    def params
      super.with_indifferent_access
    end

    # Returns only params that are resources. All params are returned 
    # if the application does not specify any resources.
    # @return [ActiveSupport::HashWithIndifferentAccess]
    def resources
      app.resources ? params.slice(*app.resources) : params
    end

    # Maps request method to an action if possible.
    # @see    MethodMap
    # @return [Symbol, nil] 
    def action
      method = request_method.downcase.to_sym
      MethodMap[method]
    end

  end # Request

end # Bulk
