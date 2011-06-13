require 'spec_helper'
require 'generators/bulk/install/install_generator'

describe 'Install generator' do
  include GeneratorSpec::TestCase
  destination File.expand_path("../../tmp", __FILE__)
  tests Bulk::Generators::InstallGenerator

  before do
    prepare_destination
    FileUtils.mkdir(::File.join(destination_root, "config"))
    ::File.open(::File.join(destination_root, "config/routes.rb"), "w") do |f|
      f.puts "Rails.application.routes.draw do\n\nresources :tasks\n\nend\n"
    end
  end

  it 'generates appropriate files' do
    run_generator

    destination_root.should have_structure {
      file "config/routes.rb" do
        contains 'match "/api/bulk" => BulkApplication'
      end

      file "app/bulk/bulk_application.rb" do
        contains "class BulkApplication < Bulk::Application"
        contains "# resources :tasks, :projects"
      end

      file "app/bulk/application_resource.rb" do
        contains "class ApplicationResource < Bulk::Resource"
        contains "# def authorize_records(action, model_class)"
        contains "# def authorize_record(action, record)"
      end
    }
  end
end
