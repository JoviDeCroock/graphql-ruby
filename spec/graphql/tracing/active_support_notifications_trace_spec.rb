# frozen_string_literal: true
require "spec_helper"

if testing_rails?
  describe GraphQL::Tracing::ActiveSupportNotificationsTrace do
    class AsnSchema < GraphQL::Schema
      class ThingSource < GraphQL::Dataloader::Source
        def fetch(ids)
          ids.map { |id| { name: "Thing #{id}" } }
        end
      end

      module Nameable
        include GraphQL::Schema::Interface
        field :name, String
        def self.resolve_type(...)
          Thing
        end
      end

      class Thing < GraphQL::Schema::Object
        implements Nameable
      end

      class Query < GraphQL::Schema::Object
        field :nameable, Nameable do
          argument :id, ID, loads: Thing, as: :thing
        end

        def nameable(thing:)
          thing
        end
      end

      query(Query)
      trace_with GraphQL::Tracing::ActiveSupportNotificationsTrace
      use GraphQL::Dataloader
      orphan_types(Thing)

      def self.object_from_id(id, ctx)
        ctx.dataloader.with(ThingSource).load(id)
      end

      def self.resolve_type(_abs, _obj, _ctx)
        Thing
      end
    end

    it "emits tracing info" do
      events = []
      callback = lambda { |name, started, finished, unique_id, payload|
        events << [name, payload]
      }
      ActiveSupport::Notifications.subscribed(callback) do
        AsnSchema.execute("{ nameable(id: 1) { name } }")
      end

      expected_names = [
        (USING_C_PARSER ? "lex.graphql" : nil),
        "parse.graphql",
        "validate.graphql",
        "analyze.graphql",
        "authorized.graphql",
        "dataloader_source.graphql",
        "execute_field.graphql",
        "resolve_type.graphql",
        "authorized.graphql",
        "execute_field.graphql",
        "execute.graphql"
      ].compact

      assert_equal expected_names, events.map(&:first)
      assert_equal [Hash], events.map(&:last).map(&:class).uniq
    end
  end
end
