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

      decode_body(env)
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

    protected

    # Decodes the request body using JSON and updates `env`.
    def decode_body(env)
      return unless media_type == 'application/json'

      body = env['rack.input'].read
      return unless body.length > 0

      env.update(
        'rack.request.form_hash'  => JSON.parse(body),
        'rack.request.form_input' => env['rack.input']
      )
    end

  end # Request

end # Bulk
