require 'spec_helper'

describe Bulk::Request do

  subject { Bulk::Request.new(mock, {}) }

  describe "#action" do
  
    map = {
      :put => :update, :post => :create,
      :delete => :delete, :get => :get
    }

    map.each_pair do |method, action|
      it "returns #{action} for request method #{method}" do
        subject.should_receive(:request_method).once.and_return(method)
        subject.action.should == action
      end
    end

  end

end
