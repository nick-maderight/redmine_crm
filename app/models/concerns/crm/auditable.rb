# frozen_string_literal: true

module Crm
  module Auditable
    extend ActiveSupport::Concern

    included do
      after_save :write_crm_audit_changes
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

    def write_crm_audit_changes
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

      # acts_as_customizable persists custom values from its own after_save
      # callback. This callback is declared after that macro in each record
      # model, so saved_changes on each value is available here.
      if respond_to?(:custom_values)
        custom_values.each do |custom_value|
          next unless custom_value.respond_to?(:saved_changes)
          next unless custom_value.saved_changes.key?('value')

          old_value, value = custom_value.saved_changes['value']
          crm_change!("cf_#{custom_value.custom_field_id}", old_value, value, actor)
        end
      end
      true
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
