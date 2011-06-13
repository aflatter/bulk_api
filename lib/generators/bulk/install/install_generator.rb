module Bulk

  module Generators

    class InstallGenerator < Rails::Generators::Base

      desc <<DESC
Description:
    Creates initializer with configuration and adds required routes
DESC

      def self.source_root
        @source_root ||= File.expand_path(File.join(File.dirname(__FILE__), 'templates'))
      end

      def routes_entry
        route 'match "/api/bulk" => BulkApplication'
      end

      def copy_app_bulk_application_resource
        template 'app/bulk/application_resource.rb'
      end

      def copy_app_bulk_bulk_application
        template 'app/bulk/bulk_application.rb'
      end

    end # InstallGenerator

  end # Generators

end # Bulk
