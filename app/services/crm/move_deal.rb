# frozen_string_literal: true

module Crm
  # Performs a stage transition while holding the deal row lock.  All
  # transition-derived fields and the stage history row commit together.
  class MoveDeal
    class << self
      def call(deal:, stage:, user:, lock_version:)
        ActiveRecord::Base.transaction do
          locked_deal = CrmDeal.unscoped.lock.find(deal_id(deal))
          expected_version = integer_version(lock_version)
          if expected_version.nil? || locked_deal.lock_version.to_i != expected_version
            raise ActiveRecord::StaleObjectError.new(locked_deal, 'update')
          end

          ensure_transitionable!(locked_deal)
          target_stage = find_stage(stage)
          unless target_stage.pipeline_id.to_i == locked_deal.pipeline_id.to_i
            invalid!(locked_deal, 'stage must belong to the deal pipeline')
          end

          # A repeated request for the current stage is an idempotent no-op;
          # in particular it does not create a second stage history row.
          return locked_deal if locked_deal.stage_id.to_i == target_stage.id.to_i

          entry_date = stage_entry_date(user)
          locked_deal.stage_id = target_stage.id
          if locked_deal.respond_to?(:crm_stage_entry_date=)
            locked_deal.crm_stage_entry_date = entry_date
          else
            locked_deal.instance_variable_set(:@crm_stage_entry_date, entry_date)
          end

          # Auditable uses this actor for the stage row; the deal callback
          # derives closed_on and follow-up fields from crm_stage_entry_date.
          previous_actor = locked_deal.instance_variable_get(:@crm_audit_user)
          locked_deal.instance_variable_set(:@crm_audit_user, user)
          begin
            locked_deal.save!
          ensure
            locked_deal.instance_variable_set(:@crm_audit_user, previous_actor)
          end
          locked_deal
        end
      end

      private

      def deal_id(deal)
        id = deal.respond_to?(:id) ? deal.id : deal
        raise ActiveRecord::RecordNotFound, 'deal is required' if id.blank?

        id
      end

      def integer_version(version)
        return nil if version.blank?
        return version if version.is_a?(Integer)
        return nil unless version.to_s.match?(/\A\d+\z/)

        version.to_i
      end

      def find_stage(stage)
        id = stage.respond_to?(:id) ? stage.id : stage
        CrmPipelineStage.unscoped.find(id)
      end

      def ensure_transitionable!(deal)
        return unless deal.respond_to?(:merged?) && deal.merged?
        invalid!(deal, 'merged deals cannot be moved')
      end

      def invalid!(record, message)
        record.errors.add(:base, message)
        raise ActiveRecord::RecordInvalid.new(record)
      end

      def stage_entry_date(user)
        return Time.now.utc.to_date if defined?(Crm::Access) && Crm::Access.feed?(user)
        return user.today if user.respond_to?(:today)

        Time.current.to_date
      end
    end
  end
end
