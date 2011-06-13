require 'bulk/routes'

module Bulk

  class Engine < Rails::Engine

    initializer "config paths" do |app|
      app.config.paths.add "app/sproutcore"
      app.config.paths.add "app/bulk"
    end

  end # Engine

end # Bulk
