# frozen_string_literal: true

module Crm
  module Auditable
    extend ActiveSupport::Concern

    included do
      attr_accessor :crm_audit_context, :crm_audit_source_ref
      after_create :write_crm_creation_audit
      after_update :write_crm_attribute_audit_changes
      # acts_as_customizable saves its custom values in an after_save callback.
      # Keep this callback after that macro's callback so update diffs can see
      # each custom value's saved_changes.
      after_save :write_crm_custom_value_audit_changes
    end

    class_methods do
      def crm_audit_fields(*fields)
        return crm_auditable_fields if fields.empty?

        @crm_audit_fields = fields.flatten.map(&:to_s).freeze
      end

      def crm_auditable_fields
        if instance_variable_defined?(:@crm_audit_fields)
          @crm_audit_fields
        elsif superclass.respond_to?(:crm_auditable_fields)
          superclass.crm_auditable_fields
        else
          []
        end
      end
    end

    # Add a history row from a service or an explicit transition. This executes
    # in the caller's transaction; it deliberately does not enqueue work.
    def crm_change!(prop_key, old_value, value, user=User.current)
      return unless defined?(CrmChange)

      CrmChange.create!(
        :record_type => self.class.name,
        :record_id => id,
        :user_id => user.respond_to?(:id) ? user.id : nil,
        :prop_key => prop_key.to_s,
        :old_value => crm_audit_value(old_value),
        :value => crm_audit_value(value),
        :created_on => Time.current
      )
    end

    private

    def write_crm_creation_audit
      return unless defined?(CrmChange)
      return unless persisted?

      actor = instance_variable_get(:@crm_audit_user) || User.current
      if crm_audit_context.to_s == 'imported'
        crm_change!('imported', nil, crm_audit_source_ref || crm_audit_external_reference, actor)
      else
        crm_change!('created', nil, crm_audit_display_name, actor)
      end
      true
    end

    def write_crm_attribute_audit_changes
      return unless defined?(CrmChange)
      return unless persisted?

      actor = instance_variable_get(:@crm_audit_user) || User.current
      fields = self.class.crm_auditable_fields
      saved_changes.each do |attribute, pair|
        next unless fields.include?(attribute.to_s)
        next if %w[created_on updated_on lock_version].include?(attribute.to_s)

        prop_key = attribute.to_s == 'archived_on' ? 'archived' : attribute.to_s
        prop_key = 'stage' if attribute.to_s == 'stage_id'
        crm_change!(prop_key, pair[0], pair[1], actor)
      end
      true
    end

    def write_crm_custom_value_audit_changes
      return unless defined?(CrmChange)
      return unless persisted?
      # Creation is represented by exactly one row from after_create.  The
      # acts_as_customizable callback runs on after_save as well, so do not
      # turn initial custom values into update rows.
      return if saved_change_to_id?
      return unless respond_to?(:custom_values)

      actor = instance_variable_get(:@crm_audit_user) || User.current
      custom_values.each do |custom_value|
        next unless custom_value.respond_to?(:saved_changes)
        next unless custom_value.saved_changes.key?('value')

        old_value, value = custom_value.saved_changes['value']
        crm_change!("cf_#{custom_value.custom_field_id}", old_value, value, actor)
      end
      true
    end

    def crm_audit_display_name
      return name if respond_to?(:name)
      return subject if respond_to?(:subject)

      id
    end

    def crm_audit_external_reference
      return external_ref if respond_to?(:external_ref)
      return external_id if respond_to?(:external_id)

      nil
    end

    def crm_audit_value(value)
      case value
      when nil
        nil
      when Array, Hash
        value.to_json
      when Date, Time, DateTime, ActiveSupport::TimeWithZone
        value.iso8601
      else
        value.to_s
      end
    end
  end
end
