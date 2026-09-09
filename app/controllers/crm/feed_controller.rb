# frozen_string_literal: true

module Crm
  class FeedController < BaseController
    CONTACT_FIELDS = %w[external_ref first_name last_name email phone job_title city linkedin_url x_url account_id].freeze
    DEAL_FIELDS = %w[external_ref name contact_id account_id].freeze
    ACTIVITY_FIELDS = %w[external_source external_id kind channel direction subject body occurred_at duration_minutes account_id contact_id deal_id].freeze

    before_action :require_feed
    accept_api_auth :create_contact, :create_deal, :create_activity, :status

    def create_contact
      attrs = feed_params(:contact)
      return unless ensure_feed_keys!(attrs, CONTACT_FIELDS)
      return render_feed_errors(nil, 'external_ref is required') if attrs['external_ref'].blank?

      if (existing = follow_merge(CrmContact.find_by(:external_ref => attrs['external_ref'])))
        return render_feed_record(existing, :contact, :ok)
      end

      contact = CrmContact.new
      return unless precheck_safe_attributes!(contact, attrs)

      contact.safe_attributes = attrs
      contact.save!
      render_feed_record(contact, :contact, :created)
    rescue ActiveRecord::RecordInvalid => e
      render_feed_errors(e.record)
    rescue ActiveRecord::RecordNotUnique
      existing = follow_merge(CrmContact.find_by(:external_ref => attrs['external_ref']))
      existing ? render_feed_record(existing, :contact, :ok) : render_feed_errors(nil, 'external_ref is already in use')
    end

    def create_deal
      attrs = feed_params(:deal)
      return unless ensure_feed_keys!(attrs, DEAL_FIELDS)
      return render_feed_errors(nil, 'external_ref is required') if attrs['external_ref'].blank?

      if (existing = follow_merge(CrmDeal.find_by(:external_ref => attrs['external_ref'])))
        return render_feed_record(existing, :deal, :ok)
      end

      contact = feed_contact(attrs['contact_id'])
      return render_feed_errors(CrmDeal.new(:contact_id => attrs['contact_id']), 'contact must be active') unless contact
      account = feed_account(attrs['account_id'])
      if attrs['account_id'].present? && !account
        return render_feed_errors(CrmDeal.new(:account_id => attrs['account_id']), 'account must be active')
      end

      pipeline = CrmPipeline.find_by(:is_default => true)
      stage = pipeline && pipeline.stages.find_by(:name => 'New')
      unless pipeline && stage && stage.kind.to_s == 'open'
        return render_feed_errors(CrmDeal.new, 'default pipeline has no New stage')
      end

      deal = CrmDeal.new
      return unless precheck_safe_attributes!(deal, attrs)

      deal.safe_attributes = attrs.slice('external_ref', 'name', 'contact_id', 'account_id')
      deal.pipeline_id = pipeline.id
      deal.stage_id = stage.id
      deal.account_id = account ? account.id : contact.account_id if deal.respond_to?(:account_id=)
      deal.amount_cents = nil if deal.respond_to?(:amount_cents=)
      deal.save!
      render_feed_record(deal, :deal, :created)
    rescue ActiveRecord::RecordInvalid => e
      render_feed_errors(e.record)
    rescue ActiveRecord::RecordNotUnique
      existing = follow_merge(CrmDeal.find_by(:external_ref => attrs['external_ref']))
      existing ? render_feed_record(existing, :deal, :ok) : render_feed_errors(nil, 'external_ref is already in use')
    end

    def create_activity
      attrs = feed_params(:activity)
      return unless ensure_feed_keys!(attrs, ACTIVITY_FIELDS)
      if attrs['external_source'].blank? || attrs['external_id'].blank?
        return render_feed_errors(nil, 'external_source and external_id are required')
      end

      existing = CrmActivity.find_by(:external_source => attrs['external_source'], :external_id => attrs['external_id'])
      return render_feed_record(existing, :activity, :ok) if existing

      activity = CrmActivity.new
      return unless precheck_safe_attributes!(activity, attrs)

      activity.safe_attributes = attrs
      activity.visibility = 'staff'
      activity.author_id = User.current.id if activity.respond_to?(:author_id=)
      unless valid_activity_parents?(activity)
        return render_feed_errors(activity, 'activity parent is invalid or merged')
      end
      activity.save!
      render_feed_record(activity, :activity, :created)
    rescue ActiveRecord::RecordInvalid => e
      render_feed_errors(e.record)
    rescue ActiveRecord::RecordNotUnique
      existing = CrmActivity.find_by(:external_source => attrs['external_source'], :external_id => attrs['external_id'])
      existing ? render_feed_record(existing, :activity, :ok) : render_feed_errors(nil, 'external identity is already in use')
    end

    def status
      payload = feed_params(:status)
      current = (Setting.plugin_redmine_crm || {}).stringify_keys
      current['feed_contract_version'] = payload['contract_version'] if payload.key?('contract_version')
      current['feed_last_success_at'] = payload['feed_last_success_at'] if payload.key?('feed_last_success_at')
      Setting.plugin_redmine_crm = current
      @feed_status = {
        :feed_contract_version => current['feed_contract_version'],
        :feed_last_success_at => current['feed_last_success_at']
      }
      respond_to do |format|
        format.api { render :status }
        format.json { render :json => @feed_status, :status => :ok }
      end
    end

    private

    def feed_params(key)
      raw = params[key] || params[key.to_s] || params
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      raw.to_h.stringify_keys.except('controller', 'action', 'format')
    end

    def crm_feed_action_allowed?
      %w[create_contact create_deal create_activity status].include?(action_name.to_s)
    end

    def ensure_feed_keys!(attrs, allowed)
      forbidden = attrs.keys - allowed
      return true if forbidden.empty?

      render :json => {:errors => {:forbidden_attributes => forbidden.sort}}, :status => :unprocessable_content
      false
    end

    def feed_contact(contact_id)
      return nil if contact_id.blank?

      contact = CrmContact.find_by(:id => contact_id)
      return nil unless contact && !contact.archived? && !contact.merged?

      contact
    end

    def feed_account(account_id)
      return nil if account_id.blank?

      account = CrmAccount.find_by(:id => account_id)
      return nil unless account && !account.archived? && !account.merged?

      account
    end

    def valid_activity_parents?(activity)
      {
        :account => CrmAccount,
        :contact => CrmContact,
        :deal => CrmDeal
      }.all? do |name, klass|
        id = activity.public_send("#{name}_id")
        next true if id.blank?

        parent = klass.find_by(:id => id)
        parent && (!parent.respond_to?(:merged?) || !parent.merged?)
      end
    end

    def follow_merge(record)
      seen = {}
      while record && record.respond_to?(:merged_into) && record.merged_into && !seen[record.id]
        seen[record.id] = true
        record = record.merged_into
      end
      record
    end

    def render_feed_record(record, type, status)
      return render_feed_errors(nil, 'record not found') unless record

      instance_variable_set("@#{type}", record)
      respond_to do |format|
        format.api { render :action => "create_#{type}", :status => status }
        format.json { render :json => feed_json(record, type), :status => status }
      end
    end

    def feed_json(record, type)
      case type
      when :contact then {:id => record.id, :external_ref => record.external_ref}
      when :deal then {:id => record.id, :external_ref => record.external_ref, :stage_id => record.stage_id}
      else {:id => record.id, :external_source => record.external_source, :external_id => record.external_id}
      end
    end

    def render_feed_errors(record, message = nil)
      errors = record && record.errors && record.errors.full_messages
      errors = [message] if errors.blank? && message.present?
      render :json => {:errors => errors || ['invalid request']}, :status => :unprocessable_content
    end
  end
end
