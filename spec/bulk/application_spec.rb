require 'spec_helper'

describe Bulk::Application do
  include Rack::Test::Methods

  def app; subject; end

  subject { Class.new(Bulk::Application).new }

  describe "#call" do

    it "calls #before_request" do
      subject.should_receive(:before_request).and_return(false)
      get "/api/bulk"
      last_response.status.should == 401
    end

  end

  describe "bulk API" do
    subject do
      Class.new(Bulk::Application) do
        resources :tasks, :projects
      end.new
    end

    let(:task) { Task.create!(:title => "Foo" )}
    let(:project) { Project.create!(:name => "Sproutcore") }

    it "gets given records" do
      get "/api/bulk", { :tasks => [task.id], :projects => [project.id] }

      last_response.body.should include_json({ :tasks => [{:title => "Foo"}]})
      last_response.body.should include_json({ :projects => [{:name => "Sproutcore"}]})
    end

    it "should not raise when records are not found" do
      get "/api/bulk", { 
        :tasks    => [task.id,    task.id + 1],
        :projects => [project.id, project.id + 1] 
      }

      last_response.body.should include_json({ :tasks => [{:title => "Foo"}]})
      last_response.body.should include_json({ :projects => [{:name => "Sproutcore"}]})
    end

    it "updates given records" do
      put "/api/bulk", {
        :tasks    => [{:title => "Bar",  :id => task.id}],
        :projects => [{:name => "Rails", :id => project.id}] 
      }

      task.reload.title.should == "Bar"
      project.reload.name.should == "Rails"
    end

    it "returns validation errors on update" do
      another_task    = Task.create(:title => "Bar")
      another_project = Project.create(:name => "jQuery")

      put "/api/bulk", {
        :tasks => [
          {:title => "Bar", :id => task.id},
          {:title => nil,   :id => another_task.id}
        ],
        :projects => [
          {:name => "Rails", :id => project.id},
          {:name => nil,     :id => another_project.id}
        ]
      }

      task.reload.title.should == "Bar"
      project.reload.name.should == "Rails"

      body = JSON.parse(last_response.body)
      body['errors']['tasks'][another_task.id.to_s].should == {'type' => 'invalid', 'data' => {'title' => ["can't be blank"]}}
      body['errors']['projects'][another_project.id.to_s].should == {'type' => 'invalid', 'data' => {'name' => ["can't be blank"]}}
    end

    it "creates given records" do
      lambda do
        lambda do
          post "/api/bulk", { :tasks => [{:title => "Bar"}],
                              :projects => [{:name => "Rails"}] }
        end.should change(Task, :count).by(1)
      end.should change(Project, :count).by(1)
    end

    it "returns validation errors on create" do
      params =  { :tasks => [{:title => "Bar", :_local_id => 10},
                             {:title => nil, :_local_id => 11}],
                  :projects => [{:name => "Rails", :_local_id => 12},
                                {:name => nil, :_local_id => 13}] }

      post "/api/bulk", params

      body = JSON.parse(last_response.body)

      body['errors']['tasks']['11'].should == {
        'type' => 'invalid', 
        'data' => {'title' => ["can't be blank"]}
      }

      body['errors']['projects']['13'].should == {
        'type' => 'invalid', 
        'data' => {'name' => ["can't be blank"]}
      }

      body['tasks'].first['title'].should == "Bar"
      body['projects'].first['name'].should == "Rails"
    end

    it "deletes given records" do
      # Touch records
      task; project

      project_count = Project.count
      task_count    = Task.count

      delete "/api/bulk", { :tasks => [task.id], :projects => [project.id] }

      Project.count.should == project_count - 1
      Task.count.should    == task_count - 1

      body = JSON.parse(last_response.body)
      body["tasks"].should == [task.id]
      body["projects"].should == [project.id]
    end

  end

end
