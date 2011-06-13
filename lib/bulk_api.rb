require 'active_support/dependencies/autoload'

module Bulk
  extend ActiveSupport::Autoload

  autoload :AbstractCollection
  autoload :Collection
  autoload :Resource
  autoload :Application
  autoload :Request
  autoload :QueryParser
  autoload :Engine

  MethodMap = {
    :get    => :get,
    :post   => :create,
    :put    => :update,
    :delete => :delete
  }.freeze
end
