require 'paper_trail'

module ActiveAdmin
  module Audit
    module HasVersions
      extend ActiveSupport::Concern
      
      RAILS_GTE_5_1 = ::ActiveRecord.gem_version >= ::Gem::Version.new("5.1.0.beta1")   
      
      module ClassMethods
        def has_versions(options = {})
          options[:also_include] ||= {}
          options[:skip] ||= []
          options[:skip] += options[:also_include].keys
          if respond_to?(:translated_attrs)
            options[:skip] += translated_attrs.map { |attr| "#{attr}_translations" }
          end

          has_paper_trail options.merge(on: [], class_name: 'ActiveAdmin::Audit::ContentVersion', meta: {
            additional_objects: ->(record) { record.additional_objects_snapshot.to_json },
            additional_objects_changes: ->(record) { record.additional_objects_snapshot_changes.to_json },
          })

          class_eval do
            define_method(:additional_objects_snapshot) do
              options[:also_include].each_with_object(VersionSnapshot.new) do |(attr, scheme), snapshot|
                snapshot[attr] =
                  if scheme.is_a? Symbol
                    send(scheme)
                  elsif scheme.empty?
                    send(attr)
                  else
                    Array(send(attr)).map do |item|
                      scheme.each_with_object({}) do |item_attr, item_snapshot|
                        item_snapshot[item_attr] = item.send(item_attr)
                      end
                    end
                  end
              end
            end

            # Will save new version of the object
            after_commit do
              if paper_trail.enabled?
                if @event_for_paper_trail
                  generate_version!
                end
              end
            end

            options_on = Array(options.fetch(:on, [:create, :update, :destroy]))

            if options_on.include?(:create)
              after_create do
                if paper_trail.enabled?
                  @event_for_paper_trail = 'create'
                end
              end
            end

            if options_on.include?(:update)
              # Cache object changes to access it from after_commit
              after_update do
                if paper_trail.enabled?
                  @event_for_paper_trail = 'update'
                  cache_version_object_changes
                end
              end
            end

            if options_on.include?(:destroy)
              # Cache all details to access it from after_commit
              before_destroy do
                if paper_trail.enabled?
                  @event_for_paper_trail = 'destroy'
                  cache_version_object
                  cache_version_object_changes
                  cache_version_additional_objects_and_changes
                end
              end
            end
          end
        end
      end

      def latest_versions(count = 5)
        versions.reorder(created_at: :desc).limit(count).rewhere(item_type: self.class.name)
      end

      def additional_objects_snapshot_changes
        prev_version = versions.last

        old_snapshot = prev_version.try(:additional_objects) || VersionSnapshot.new
        new_snapshot = additional_objects_snapshot

        old_snapshot.diff(new_snapshot)
      end

      private

      def cache_version_object
        @version_object_cache ||= paper_trail.object_attrs_for_paper_trail(false)
      end

      def cache_version_object_changes
        record = paper_trail.instance_variable_get(:@record)
        @version_object_changes_cache ||= (RAILS_GTE_5_1 ? record.saved_changes : record.changes)
      end

      def cache_version_additional_objects_and_changes
        @version_additional_objects_and_changes_cache ||= paper_trail.merge_metadata_into({})
      end

      def clear_version_cache
        @version_object_cache = nil
        @version_object_changes_cache = nil
        @version_additional_objects_and_changes_cache = nil
      end

      def generate_version!
        data = {
          event: @event_for_paper_trail,
          object: cache_version_object.to_json,
          object_changes: cache_version_object_changes.to_json,
          whodunnit: PaperTrail.request.whodunnit.try(:id),
          item_type: self.class.name,
          item_id: id,
        }

        PaperTrail::Version.create! data.merge!(cache_version_additional_objects_and_changes)

        clear_version_cache
      end
    end
  end
end
