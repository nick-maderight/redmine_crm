# frozen_string_literal: true

module Crm
  # Dashboard "New lead" workflow.  Email collisions are deliberately a
  # result, not an implicit reuse or merge: the caller must choose the existing
  # contact or explicitly create the new contact without that email.
  class CreateLead
    class Result
      attr_reader :contact, :account, :deal, :activity, :existing_contact, :errors, :warning

      def initialize(contact: nil, account: nil, deal: nil, activity: nil,
                     existing_contact: nil, warning: false, errors: nil, created: false)
        @contact = contact
        @account = account
        @deal = deal
        @activity = activity
        @existing_contact = existing_contact
        @warning = warning
        @errors = errors
        @created = created
      end

      def warning?
        warning
      end

      def success?
        @created && @deal.present?
      end

      def created?
        @created
      end

      def contact_collision?
        existing_contact.present?
      end

      def to_h
        {
          :contact => contact,
          :account => account,
          :deal => deal,
          :activity => activity,
          :existing_contact => existing_contact,
          :warning => warning?,
          :errors => errors
        }
      end
    end

    class << self
      def call(params, user)
        attrs = normalize_params(params)
        email = normalize_email(attrs[:email])
        existing = find_active_contact(email)
        existing ||= find_active_contact_by_id(attrs[:existing_contact_id])

        if existing && !use_existing?(attrs) && !create_without_email?(attrs)
          return Result.new(:existing_contact => existing, :warning => true)
        end

        ActiveRecord::Base.transaction do
          account = resolve_account(attrs)
          contact = if existing && use_existing?(attrs)
                      existing
                    else
                      build_contact(attrs, account, email: create_without_email?(attrs) ? nil : email).tap(&:save!)
                    end

          deal = build_deal(attrs, contact, account)
          deal.save!

          activity = build_first_note(attrs, contact, account, deal, user)
          activity&.save!

          Result.new(
            :contact => contact,
            :account => account || contact.account,
            :deal => deal,
            :activity => activity,
            :created => true
          )
        end
      end

      private

      def normalize_params(params)
        raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
        raw = raw[:lead] || raw['lead'] if raw.respond_to?(:key?) && (raw.key?(:lead) || raw.key?('lead'))
        hash = raw.respond_to?(:to_h) ? raw.to_h : {}
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value
        end
      end

      def normalize_email(value)
        value.to_s.strip.downcase.presence
      end

      def find_active_contact(email)
        return nil if email.blank?
        CrmContact.active.where('LOWER(email) = ?', email).first
      end

      def find_active_contact_by_id(id)
        return nil if id.blank?
        CrmContact.active.find_by(:id => id)
      end

      def use_existing?(attrs)
        truthy?(attrs[:use_existing]) ||
          attrs[:email_collision_action].to_s == 'use_existing' ||
          attrs[:existing_contact_id].present?
      end

      def create_without_email?(attrs)
        truthy?(attrs[:create_without_email]) ||
          attrs[:email_collision_action].to_s == 'create_without_email'
      end

      def truthy?(value)
        value == true || value.to_s.in?(%w[1 true yes on])
      end

      def resolve_account(attrs)
        if attrs[:account_id].present?
          account = CrmAccount.active.find(attrs[:account_id])
          reject_merged!(account)
          return account
        end

        name = attrs[:account_name].presence || attrs[:account].presence
        return nil if name.blank? || name.is_a?(Hash)

        CrmAccount.create!(:name => name.to_s.strip)
      end

      def build_contact(attrs, account, email:)
        CrmContact.new(
          :first_name => attrs[:first_name],
          :last_name => attrs[:last_name],
          :email => email,
          :phone => attrs[:phone],
          :job_title => attrs[:job_title],
          :city => attrs[:city],
          :linkedin_url => attrs[:linkedin_url],
          :x_url => attrs[:x_url],
          :account_id => account&.id
        )
      end

      def build_deal(attrs, contact, account)
        pipeline = CrmPipeline.where(:is_default => true).first
        unless pipeline
          deal = CrmDeal.new(:name => attrs[:deal_name].presence || attrs[:name])
          deal.errors.add(:base, 'a default pipeline is required')
          raise ActiveRecord::RecordInvalid.new(deal)
        end

        stage = pipeline.stages.where(:kind => 'open').order(:position, :id).first
        unless stage
          deal = CrmDeal.new(:name => attrs[:deal_name].presence || attrs[:name])
          deal.errors.add(:base, 'the default pipeline must have an open stage')
          raise ActiveRecord::RecordInvalid.new(deal)
        end

        CrmDeal.new(
          :name => attrs[:deal_name].presence || attrs[:name],
          :account_id => account&.id || contact.account_id,
          :contact_id => contact.id,
          :pipeline_id => pipeline.id,
          :stage_id => stage.id
        )
      end

      def build_first_note(attrs, contact, account, deal, user)
        body = attrs[:first_note].presence || attrs[:note].presence
        return nil if body.blank?

        CrmActivity.new(
          :kind => 'note',
          :body => body,
          :occurred_at => attrs[:occurred_at].presence || Time.current,
          :account_id => account&.id || contact.account_id || deal.account_id,
          :contact_id => contact.id,
          :deal_id => deal.id,
          :author_id => user.respond_to?(:id) ? user.id : nil,
          :visibility => 'staff'
        )
      end

      def reject_merged!(record)
        return unless record.respond_to?(:merged?) && record.merged?

        record.errors.add(:base, 'merged records cannot be used for a lead')
        raise ActiveRecord::RecordInvalid.new(record)
      end
    end
  end
end
