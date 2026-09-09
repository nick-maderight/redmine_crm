# frozen_string_literal: true

module Crm
  module ActiveParentAssociation
    extend ActiveSupport::Concern

    included do
      validate :validate_crm_parent_associations
    end

    class_methods do
      def crm_parent(*names)
        return crm_parent_associations if names.empty?

        @crm_parent_associations = names.flatten.map(&:to_sym).freeze
      end

      def crm_parent_associations
        if instance_variable_defined?(:@crm_parent_associations)
          @crm_parent_associations
        elsif superclass.respond_to?(:crm_parent_associations)
          superclass.crm_parent_associations
        else
          []
        end
      end
    end

    # Activities are intentionally allowed to be appended to a plain archived
    # parent by the feed. Every other child write requires active parents.
    def crm_archived_parent_allowed?
      false
    end

    private

    def validate_crm_parent_associations
      self.class.crm_parent_associations.each do |association_name|
        parent = public_send(association_name)
        next unless parent

        if parent.respond_to?(:merged?) ? parent.merged? : parent.respond_to?(:merged_into_id) && parent.merged_into_id.present?
          errors.add(association_name, :merged_parent)
        elsif parent.respond_to?(:archived?) ? parent.archived? : parent.respond_to?(:archived_on) && parent.archived_on.present?
          errors.add(association_name, :archived_parent) unless crm_archived_parent_allowed?
        end
      end
    end
  end
end
