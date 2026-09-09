# frozen_string_literal: true

module Crm
  # Staff-only account/contact merge transaction.  The source remains as an
  # archived lineage row (including its external_ref); all declared child and
  # bridge references move to the survivor without rewriting CRM history.
  class Merge
    class << self
      def call(source:, target:, user:)
        validate_types!(source, target)

        ActiveRecord::Base.transaction do
          locked_source, locked_target = lock_parents(source, target)
          validate_parents!(locked_source, locked_target)

          if locked_source.is_a?(CrmContact)
            validate_contact_closure!(locked_source, locked_target)
            repoint_contact_children!(locked_source, locked_target, user)
          else
            repoint_account_children!(locked_source, locked_target, user)
          end

          merge_custom_values!(locked_source, locked_target, user)
          locked_source.reload
          merged_into_id = locked_target.id
          locked_source.merged_into_id = merged_into_id if locked_source.has_attribute?(:merged_into_id)
          locked_source.save!
          locked_source.archive!(user)

          locked_source.crm_change!(:merged_into, nil, merged_into_id, user) if locked_source.respond_to?(:crm_change!)
          locked_target.crm_change!(:merged_from, nil, locked_source.id, user) if locked_target.respond_to?(:crm_change!)
          source.reload if source.object_id != locked_source.object_id
          locked_target
        end
      end

      # The merge confirmation page uses this read-only count map.
      def preview(source, target, _user = User.current)
        validate_types!(source, target)
        return {} if source.id.blank? || target.id.blank?

        if source.is_a?(CrmAccount)
          {
            :contacts => CrmContact.unscoped.where(:account_id => source.id).count,
            :activities => CrmActivity.unscoped.where(:account_id => source.id).count,
            :deals => CrmDeal.unscoped.where(:account_id => source.id).count,
            :links => CrmLink.where(:account_id => source.id).count,
            :account_projects => CrmAccountProject.where(:account_id => source.id).count,
            :custom_values => custom_value_count(source)
          }
        else
          {
            :activities => CrmActivity.unscoped.where(:contact_id => source.id).count,
            :deals => CrmDeal.unscoped.where(:contact_id => source.id).count,
            :links => CrmLink.where(:contact_id => source.id).count,
            :custom_values => custom_value_count(source)
          }
        end
      end

      private

      def validate_types!(source, target)
        unless source.is_a?(CrmAccount) && target.is_a?(CrmAccount) ||
               source.is_a?(CrmContact) && target.is_a?(CrmContact)
          raise ArgumentError, 'merge requires two accounts or two contacts'
        end
      end

      def lock_parents(source, target)
        klass = source.class
        ids = [source.id, target.id].map(&:to_i).sort
        rows = klass.unscoped.lock.where(:id => ids).order(:id).to_a
        locked_source = rows.find {|row| row.id.to_i == source.id.to_i}
        locked_target = rows.find {|row| row.id.to_i == target.id.to_i}
        raise ActiveRecord::RecordNotFound unless locked_source && locked_target

        [locked_source, locked_target]
      end

      def validate_parents!(source, target)
        invalid!(source, 'source and target must be different') if source.id.to_i == target.id.to_i
        invalid!(source, 'source must be active') if source.respond_to?(:archived?) && source.archived?
        invalid!(target, 'target must be active') if target.respond_to?(:archived?) && target.archived?
        invalid!(source, 'source is already merged') if source.respond_to?(:merged?) && source.merged?
        invalid!(target, 'target is already merged') if target.respond_to?(:merged?) && target.merged?
      end

      def validate_contact_closure!(source, target)
        target_account_id = source_account_id(target)
        account_ids = []
        account_ids << source_account_id(source)

        CrmActivity.unscoped.where(:contact_id => source.id, :visibility => 'shared').includes(:contact, :deal).find_each do |activity|
          account_ids << activity.account_id
          account_ids << activity.contact&.account_id
          account_ids << activity.deal&.account_id
        end
        CrmDeal.unscoped.where(:contact_id => source.id).pluck(:account_id).each {|id| account_ids << id}

        CrmLink.where(:contact_id => source.id).includes(:deal).find_each do |link|
          account_ids << link.account_id
          account_ids << link.deal&.account_id
          account_ids << source_account_id(source) if link.account_id.nil? && link.deal_id.nil?
        end

        conflicting = account_ids.compact.map(&:to_i).uniq.reject {|id| id == target_account_id.to_i }
        invalid!(source, 'contact merge crosses account boundaries') if conflicting.any? ||
          (target_account_id.nil? && account_ids.compact.any?)
      end

      def repoint_account_children!(source, target, user)
        CrmContact.unscoped.where(:account_id => source.id).lock.order(:id).find_each do |contact|
          contact.update_columns(:account_id => target.id, :updated_on => Time.current)
        end

        CrmDeal.unscoped.where(:account_id => source.id).lock.order(:id).find_each do |deal|
          deal.update_columns(:account_id => target.id, :updated_on => Time.current)
        end

        CrmActivity.unscoped.where(:account_id => source.id).lock.order(:id).find_each do |activity|
          activity.update_columns(:account_id => target.id, :updated_on => Time.current)
        end

        repoint_links!(:account_id, source.id, target.id, target, user)
        repoint_account_projects!(source, target, user)
      end

      def repoint_contact_children!(source, target, user)
        CrmDeal.unscoped.where(:contact_id => source.id).lock.order(:id).find_each do |deal|
          deal.update_columns(:contact_id => target.id, :updated_on => Time.current)
        end

        CrmActivity.unscoped.where(:contact_id => source.id).lock.order(:id).find_each do |activity|
          activity.update_columns(:contact_id => target.id, :updated_on => Time.current)
        end

        repoint_links!(:contact_id, source.id, target.id, target, user)
      end

      def repoint_links!(column, source_id, target_id, target, user)
        CrmLink.where(column => source_id).lock.order(:id).to_a.each do |link|
          duplicate = CrmLink.where(column => target_id, :issue_id => link.issue_id).
            where.not(:id => link.id).first
          if duplicate
            link.destroy!
          else
            issue_id = link.issue_id
            link.update_columns(column => target_id)
            target.crm_change!(:link_issue, nil, issue_id, user) if target.respond_to?(:crm_change!)
          end
        end
      end

      def repoint_account_projects!(source, target, user)
        CrmAccountProject.where(:account_id => source.id).lock.order(:project_id).to_a.each do |link|
          duplicate = CrmAccountProject.where(:project_id => link.project_id).
            where.not(:account_id => source.id).first
          if duplicate
            link.destroy!
          else
            project_id = link.project_id
            link.update_columns(:account_id => target.id)
            target.crm_change!(:link_project, nil, project_id, user) if target.respond_to?(:crm_change!)
          end
        end
      end

      def merge_custom_values!(source, target, user)
        return unless source.respond_to?(:custom_values) && target.respond_to?(:custom_values)

        source.custom_values.to_a.each do |source_value|
          target_value = target.custom_values.where(:custom_field_id => source_value.custom_field_id).first
          prop_key = "cf_#{source_value.custom_field_id}"
          if target_value.nil?
            source_value.update_columns(:customized_type => target.class.name, :customized_id => target.id)
            target.crm_change!(prop_key, nil, source_value.value, user) if source_value.value.present? && target.respond_to?(:crm_change!)
          elsif target_value.value.blank? && source_value.value.present?
            old_value = target_value.value
            target_value.update_columns(:value => source_value.value)
            source_value.destroy!
            target.crm_change!(prop_key, old_value, target_value.value, user) if target.respond_to?(:crm_change!)
          else
            source_value.destroy! unless source_value.equal?(target_value)
          end
        end
      end

      def custom_value_count(record)
        record.respond_to?(:custom_values) ? record.custom_values.count : 0
      end

      def source_account_id(record)
        record.respond_to?(:account_id) ? record.account_id : nil
      end

      def invalid!(record, message)
        record.errors.add(:base, message)
        raise ActiveRecord::RecordInvalid.new(record)
      end
    end
  end
end
