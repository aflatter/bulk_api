require 'active_support/core_ext/module/delegation'
require 'bulk/abstract_collection'

module Bulk
  class Collection < AbstractCollection
    class Error < Struct.new(:type, :data)
      def to_hash
        h = {:type => type}
        h[:data] = data if data
        h
      end
    end

    class Errors < AbstractCollection
      attr_reader :collection

      def initialize(collection)
        @collection = collection
        super()
      end

      def set(id, error, data = nil)
        super(id, Error.new(error, data))
      end
    end

    # Returns errors for the records
    def errors
      @errors ||= Errors.new(self)
    end

    def to_hash(name, opts = {})
      only_ids = opts[:only_ids]

      result = {}
      records = []

      each do |id, record|
        next if errors.get(id)

        if only_ids
          records << record.id
        else
          record_hash = record.as_json(opts[:as_json_options])

          # TODO: Handle me on a per model basis and somewhere else.
          if defined?(ActiveRecord)
            if ActiveRecord::Base.include_root_in_json
              record_hash = record_hash[record_hash.keys.first]
            end
          end

          records << record_hash
        end
      end

      errors.each do |id, error|
        result[:errors] ||= {name => {}}
        result[:errors][name][id] = error.to_hash
      end

      result[name] = records

      result
    end

  end

end
