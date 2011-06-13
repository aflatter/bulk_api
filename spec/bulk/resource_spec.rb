require 'spec_helper'
require 'action_dispatch/testing/integration'

describe Bulk::Resource do

  let(:request) { mock }
  subject { described_class.new(request, 'tasks') }

  module ResourceHelpers

    def get
      @task    = Task.create!(:title => 'task', :done => true)
      subject.get([@task.id])
    end

    def update
      @task    = Task.create(:title => 'My Task')
      params = [{:_local_id => '5', :title => 'task', :done => true, :id => @task.id}]
      subject.update(params)
    end

    def create
      params = [{:_local_id => '10', :title => 'task', :done => true}]
      subject.create(params)
    end

    def delete
      @task = Task.create(:title => 'task', :done => true)
      subject.delete([@task.id])
    end

  end

  include ResourceHelpers

  shared_examples_for "an action that authorizes records" do |opts|

    def get
      @first_task  = Task.create(:title => 'Cool task, yo!')
      @second_task = Task.create(:title => 'Access Denied')

      yield if block_given?

      subject.get([@first_task.id, @second_task.id])
    end

    def create
      yield if block_given?

      subject.create([
        {:_local_id => '5', :title => 'Cool task, yo!'},
        {:_local_id => '6', :title => 'Access Denied'}
      ])
    end

    def update
      @first_task  = Task.create(:title => 'Cool task, yo!')
      @second_task = Task.create(:title => 'Access Denied')

      yield if block_given?

      subject.update([
        {:_local_id => '5', :done => true, :id => @first_task.id},
        {:_local_id => '6', :done => true, :id => @second_task.id}
      ])
    end

    def delete
      @first_task  = Task.create(:title => 'Cool task, yo!')
      @second_task = Task.create(:title => 'Access Denied')

      yield if block_given?

      subject.delete([@first_task.id, @second_task.id])
    end
    
    it "runs callbacks in order" do
      subject.should_receive(:authorize_records).once.ordered.and_return(true)
      subject.should_receive(:authorize_record).twice.ordered.and_return(true)

      send(opts[:action])
    end

    # Note: I know that this stuff is a bit meta, but it's important 
    #       to have it in one place.
    it "returns error for unauthorized record" do

      result = send(opts[:action]) do

        subject.should_receive(:authorize_record).twice do |action, record|
          action.should == opts[:action]
          record.title == 'Cool task, yo!'
        end

        subject.should_receive(:authorize_records) do |action, model_class|
          action.should == opts[:action]
          model_class.should == Task
        end

      end

      result['tasks'].length.should == 1

      errors = result[:errors]['tasks']
      errors.length.should == 1
      errors.values.first[:type].should == 'forbidden'
    end

  end

  shared_examples_for "an action that filters attributes" do |opts|

    # TODO: Refactor
    it "filters attributes using as_json_options" do
      subject.should_receive(:as_json_options).and_return(:only => [:title])
      result = send(opts[:action]).to_json
      expected = { :tasks => [{:title => "task"}] }
      result.should include_json(expected)
      not_expected = { :tasks => [{:done => true}] }
      result.should_not include_json(not_expected)
    end

  end

  describe ".model_class" do

    it "sets attribute when called with argument" do
      klass = Class.new(Bulk::Resource) do
        model_class String
      end
     
      klass.model_class.should     == String
      klass.new(request).model_class.should == String
    end

    it "determines model from resource name" do
      Bulk::Resource.new(request, 'tasks').model_class.should == Task
    end

    it "returns model class if both model class and resource name are set" do
      klass = Class.new(Bulk::Resource) do
        model_class String
      end
    
      klass.new(request, 'tasks').model_class.should == String
    end

    it "raises error if class can not be determined" do
      lambda { Bulk::Resource.new(request, 'bananas').model_class }.should raise_error
    end

    # TODO: Do we need that? Would probably be cool.
    it "falls back to class name if model class and resource name are not set"

  end


  describe "#get" do

    it_behaves_like "an action that filters attributes", :action => :get
    it_behaves_like "an action that authorizes records", :action => :get

    before do
      @tasks = [Task.create(:title => "First!"), Task.create(:title => "Foo")]
    end

    it "fetches records with given ids" do
      result = subject.get(@tasks.map(&:id))
      includes_all_records(result)
    end

    it "fetches all the records with :all argument" do
      result = subject.get('all')
      result['tasks'].length.should == 2
      includes_all_records(result)
    end

    it "should fetch all the records without arguments" do
      result = subject.get
      result['tasks'].length.should == 2
      includes_all_records(result)
    end

    def includes_all_records(result)
      result['tasks'].each do |task|
        record = @tasks.find { |t| t.id == task['id'] }
        record.should_not be_nil
      end
      true
    end

  end

  describe "#create" do

    it_behaves_like "an action that filters attributes", :action => :create
    it_behaves_like "an action that authorizes records", :action => :create

    it "creates records from given data hashes" do
      result = nil

      lambda {
        result = subject.create([
          {:title => "Add more tests", :_local_id => 10},
          {:title => "Be nice", :done => true, :_local_id => 5}
        ])
      }.should change(Task, :count).by(2)

      result['tasks'].length.should == 2

      first_task = result['tasks'].find { |t| t['_local_id'] == 10 }
      first_task.should_not be_nil
      first_task['title'].should == "Add more tests"

      second_task = result['tasks'].find { |t| t['_local_id'] == 5 }
      second_task.should_not be_nil
      second_task['title'].should == "Be nice"
      second_task['done'].should  == true
    end

    it "returns errors in a hash with local_id as index for records" do
      result = subject.create([
        {:title => "Add more tests", :_local_id => 10},
        {:_local_id => 11}
      ])

      error = result[:errors]['tasks']['11']
      error[:data][:title].should == ["can't be blank"]
      error[:type].should == :invalid

      result['tasks'].length.should == 1
      result['tasks'][0]['_local_id'].should == 10
      result['tasks'][0]['title'].should == "Add more tests"
    end

  end

  describe "#update" do

    it_behaves_like "an action that authorizes records", :action => :update
    it_behaves_like "an action that filters attributes", :action => :update

    it "updates records from given data hashes" do
      task = Task.create(:title => "Learn teh internets!")

      collection = subject.update([
        {:title => "Learn the internets!", :id => task.id}
      ])

      task.reload.title.should == "Learn the internets!"
    end

    it "skips non-existing records" do
      task = Task.create(:title => "Learn teh internets!")

      result = subject.update([
        {:title => "blah!", :id => 1},
        {:title => "Learn the internets!", :id => task.id}
      ])

      task.reload.title.should == "Learn the internets!"
      result['tasks'].length.should == 1
    end

    it "returns errors when validation fails" do
      first_task  = Task.create(:title => "Learn teh internets!")
      second_task = Task.create(:title => "Lame task")

      result = subject.update([
        {:id => first_task.id,  :title => "Changed", :_local_id => 10},
        {:id => second_task.id, :title => nil,       :_local_id => 11}
      ])

      error = result[:errors]['tasks'][second_task.id.to_s]
      error[:type].should == :invalid
      error[:data][:title].should == ["can't be blank"]

      result['tasks'][0]['title'].should == 'Changed'
      result['tasks'].length.should == 1
    end
  end

  describe "#delete" do

    it_behaves_like "an action that authorizes records", :action => :delete
    
    it "returns only ids"

    it "skips non existing records" do
      task = Task.create(:title => "Learn teh internets!")
      result = subject.delete([task.id, task.id + 1])
      result['tasks'].should == [task.id]
    end

    it "deletes given records" do
      first_task  = Task.create(:title => "First")
      second_task = Task.create(:title => "Second", :invulnerable => true)

      task_ids = [first_task.id, second_task.id]

      result = nil
      lambda {
        result = subject.delete(task_ids)
      }.should change(Task, :count).by(-2)

      error = result[:errors]['tasks'][second_task.id.to_s]
      error[:data][:base].should == ["You can't destroy me noob!"]
      error[:type].should == :invalid
    end

  end

end
