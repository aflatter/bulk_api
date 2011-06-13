# WARNING: Still under heavy maintenance ;)

I think I should write that this gem is not yet production
ready and it will probably take some API changes without deprecation
warnings, so you should probably wait a bit if you want
to use that.

# BulkApi

`bulk_api` makes integrating Sproutcore and Rails applications dead simple. It handles all the communication and allows to take advantage of bulk operations, which can make your application much faster. To use that plugin you will also need `BulkDataSource`, which will handle the Sproutcore side of things..

The `bulk_api` approach differs from REST APIs that you're probably used to; thus it needs to be handled differently. The goal is to cut the number of requests you need to do: It can handle many records (and many types of records) with one request. If you want to read more about how the API looks from the HTTP point of view, please refer to the "HTTP Api" section.

## Example

https://github.com/drnic/todos-bulk-api-demo

## Installing

After following this guide you will have a setup like this:

  * `$RAILS_ROOT/app/bulk` is the path where your resource definitions live
  * `/api/bulk` is routed to serve the API

### Rails

Add this line to Gemfile and run bundle install:

```ruby
gem 'bulk_api', :git => 'http://github.com/aflatter/bulk_api.git'
```

Add this line to your `routes.rb`:

```ruby
match '/bulk/api' => Bulk::Application
```

### Sproutcore

Now you need to configure your application. Install `BulkDataSource`:

```
cd <sproutcore_root>
mkdir frameworks # In case it does not exist yet
git clone https://github.com/drogus/bulk_data_source.git frameworks/bulk_data_source
```

Change your `Buildfile` to include it:

```ruby
config :all, :required => [:sproutcore, "sproutcore/core_foundation", "bulk_data_source"]
```

Configure your store:

```javascript
YourApp = SC.Application.create({
  store: SC.Store.create().from('SC.BulkDataSource')
});
```

The last thing that you need to do is to set resource names for your models. `BulkDataSource` assumes that you have resourceName attribute set on your model. If you don't have such attributes, you can add it like that:

```javascript
Todos.Todo = SC.Record.extend({
  // your code here
});
Todos.Todo.resourceName = 'todo';
```

## Customization

If you don't have any specific needs like authentication or authorization, you're good to go with such simple configuration. In other cases you will need to do a bit more to integrate your application.

When using bulk api you can handle things on 3 levels:

1) All requests
2) Particular record type
3) Individual record

Let's see how to handle things on all of the 3 levels to add your own logic (like authentication or authorization).

The methods used for records manipulation are:

* get
* create
* update
* delete

### Control which resources are exposed

By default Bulk Api plugin handles all models. This is probably not what you want. Customization is done by subclassing `Bulk::Application`:

```ruby
# app/bulk/bulk_application.rb
class BulkApplication < Bulk::Application
  resources :tasks, :projects
end

# config/routes.rb
match '/bulk/api' => BulkApplication
```

Because `bulk_api` is built on Rack, you can use other middleware to alter its behaviour.

### Authentication

```ruby
# app/bulk/bulk_application.rb
class BulkApplication < Bulk::Application
  def before_request(request)
    request.env['warden'].authenticate
  end
end
```

### Authorization

If some of your logic is common for all resources, you can define an `ApplicationResource`. This class is used if you do not implement a more specific resource.  Just like `ApplicationController` in rails, you can use that as a base class for all of your resources. 

There are 2 different authorization callbacks that you can use:

* `authorize_records(action, model_class)` - this callback is run before handling each type of resource, if it returns false, a `forbidden`` error is added to all of the records.
* `authorize_record(action, record)` - this callback is run for each of the records. If it returns false, a `forbidden` error is added to the given record.

```ruby
# app/bulk/application_resource.rb
class ApplicationResource < Bulk::Resource

  # Allow only get requests and only for the tasks resource:
  def authorize_records(action, model_class)
    model_class == Task && action == :get
  end

  # Check if the record belongs to the user
  def authorize_record(action, record)
    request.env['current_user'].id == record.user_id
  end

end
```

### Params filtering

While preparing your API, you will probably need to filter parameters
that user can set on your models. The easiest way to do it is to set
params_accessible or params_protected callbacks:

```ruby
class ApplicationResource < Bulk::Resource
  def params_accessible(klass)
    { :tasks    => [:title, :done],
                    :projects => [:name] }
  end

  # or:

  def params_protected(klass)
    { :tasks => [:created_at, :updated_at] }
  end
end
```

You can also set it for individual resource classes. In such case this
will overwrite the one that's set in ApplicationResource.

### Attributes filtering

If you want to filter the attributes that are sent in a response, the
easiest way to do it is to use standard Rails mechanism for that -
override as_json method in your model:

```ruby
class MyModel < ActiveRecord::Base
  def as_json(options={})
    super(:only => [:email, :avatar], :include =>[:addresses])
  end
end
```

With some applications that's not enough, though. If you have several
user roles, the chances are that you will need to differentiate
responses based on user rights. In that case you can use as_json
callback. Value returned from that callback will be passed to the
record's as_json method:

```ruby
class ApplicationResource < Bulk::Resource
  def as_json(record)
    # return hash that will be passed to record's as_json
    { :only => [:email] }
  end
end
```

You can also override that method in individual resource classes.

### Implementing resources 

Sometimes you may want to implement specific application logic to one of the resources. Or you don't want to end up with Switch Driven Development in one of you authenticate callbacs. In such cases, the easiest way to handle resource specific code is to create an ApplicationResouce subclass that you can use to override standard behavior. There is a generator to make things easy for you:

```
rails g bulk:resource task
```

This will create the following file:

```ruby
# app/bulk/task_resource.rb
class TaskResource < ApplicationResource
end
```

If you do nothing else, Rails will automatically return records by retrieving them using ActiveRecord. You can customize any of the default behavior by overriding methods on the resource class. As you already now the main methods that are used to fetch and modify records are: get, create, update, delete. Let's see how you can override those methods:

```ruby
# app/resources/task_resource.rb
class TaskResource < Sproutcore::Resource

  def get(ids)
    # ids is an array with records that we need to fetch

    collection = super(ids)

    # collection is an instance of Bulk::Collection class that keeps
    # fetched records, please check the rest of the README and the docs
    # to see how you can manipulate records in collection
    collection
  end

  def create(records)
    # records is an array of hashes with data that will be used
    # to create new records e.g.:
    # [{:title => "First", :done => false, :_local_id => 1},
    #  {:title => "", :done => true, :_local_id => 3}]
    # _local_id is needed to identify the records in sproutcore
    # application, since they do not have an id yet

    collection = super(records)

    collection
  end

  def update(records)
    # records array is very similar to the array from create method,
    # but this time we should get data with id, like:
    # [{:id => 1, :title => "First (changed!)", :done => false},
    #  {:id => 2, :title => ""}]

    collection = super(records)

    collection
  end

  def delete(ids)
    # similarly to get method, we get array of ids to delete

    collection = super(ids)

    collection
  end
end
```

While overriding records you can use super to handle the actions with default behavior or reimplement them yourself. In latter case you just need to make sure that you properly construct collection.

### Bulk::Collection

Bulk::Collection is a container for records and is used to construct response from. It has a few handy methods to easily modify collection, for more please refer to documantation.

```ruby
collection = Bulk::Colection.new
collection.set(1, record) # add record with identifier '1', identifier is then used while constructing response
                          # most of the time it's id or _local_id (the latter one is mainly for create)

collection.errors.set(1, :access_denied) # add error that will be passed to DataSource
                                         # notice that these errors are not the same as validation errors,
                                         # this is more general way to tell DataSource what's going on
collection.delete(1, record) # remove the record
```

## Http Bulk API

The point of using bulk API is to cut the requests number. Because of its nature it can't be handled efficiently using standard REST API. The bulk API is designed to handle many records and record types in one request. Let's look how does GET request can look like with bulk API;

```
POST /bulk/api
{
  'todos': [
    {'title': "First todo", 'done': false, '_storeKey': '3'},
    {'title': "Second todo", 'done': true, '_storeKey': '10'}
  ],
  'projects': [
    {'name': "Sproutcore todolist", '_storeKey': '12'}
  ]
}
```

As you can see we POST some new items to our application. Rails application will then respond with list of created records:

```
{
  'todos': [
    {'id': 1, 'title': "First todo", 'done': false, '_storeKey': '3'}
  ],
  'projects': [
    {'id': 1, 'name': "Sproutcore todolist", '_storeKey': '12'}
  ]
  'errors': {
    'todos': {
    }
  }
}
```

As you can see, all the records that were created have id attached now and there is additional attribute 'errors' that tells us what went wrong during validation.
