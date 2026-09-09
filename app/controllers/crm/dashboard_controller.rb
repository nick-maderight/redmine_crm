# frozen_string_literal: true

module Crm
  class DashboardController < BaseController
    before_action :require_login

    def index
      prepare_dashboard
      render :index
    end

    def create_lead
      return head(:forbidden) unless Crm::Access.staff?(User.current)

      payload = params[:lead] || params[:create_lead] || params.permit!.to_h
      result = Crm::CreateLead.call(payload, User.current)
      record = create_lead_record(result)
      if create_lead_success?(result, record)
        respond_to do |format|
          format.html { redirect_to crm_deal_path(record) }
          format.json { render :json => {:id => record.id, :deal_id => record.id}, :status => :created }
        end
      else
        render_lead_failure(result, payload)
      end
    rescue ActiveRecord::RecordInvalid => e
      render_lead_failure(e.respond_to?(:record) ? e.record : nil, payload, e)
    rescue ActiveRecord::RecordNotUnique
      render_lead_failure(nil, payload)
    end

    private

    def create_lead_record(result)
      return result.record if result.respond_to?(:record) && result.record
      return result.deal if result.respond_to?(:deal) && result.deal
      result if result.respond_to?(:persisted?)
    end

    def create_lead_success?(result, record)
      success = result.respond_to?(:success?) ? result.success? : record && record.persisted?
      success && record && record.respond_to?(:persisted?) && record.persisted?
    end

    def lead_warning?(result)
      return false unless result
      return result.warning? if result.respond_to?(:warning?)
      result.respond_to?(:warning) && result.warning
    end

    def lead_contact_record?(record)
      record && record.respond_to?(:email) && record.respond_to?(:first_name)
    end

    def render_lead_failure(result, payload, exception = nil)
      @lead_result = exception ? nil : result
      @lead_record = if exception && exception.respond_to?(:record)
                       exception.record
                     elsif result.respond_to?(:record)
                       result.record
                     elsif result.respond_to?(:errors) && !result.respond_to?(:success?)
                       result
                     end
      @lead_existing_contact = result.existing_contact if result && result.respond_to?(:existing_contact)
      if @lead_existing_contact.nil? && lead_warning?(result) && result.respond_to?(:record) && lead_contact_record?(result.record)
        @lead_existing_contact = result.record
      end
      @lead_errors = if exception
                       @lead_record.respond_to?(:errors) ? @lead_record.errors : [l(:text_crm_lead_conflict, :default => 'The lead could not be created.')]
                     elsif result && result.respond_to?(:errors)
                       result.errors
                     else
                       [l(:text_crm_lead_conflict, :default => 'The lead could not be created because it conflicts with an existing record.')]
                     end
      @lead_values = lead_payload_hash(payload)
      prepare_dashboard
      @lead = @lead_record || @lead_result || @lead_values
      render :index, :status => :unprocessable_content
    end

    def lead_payload_hash(payload)
      raw = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
      raw.respond_to?(:to_h) ? raw.to_h : {}
    end

    def prepare_dashboard
      if Crm::Access.contractor?(User.current)
        @accounts = visible_accounts.to_a
        @contacts = visible_contacts.to_a
        @recent_activities = recent_activities
        @stale = @due = @overdue = @my_open_deals = []
        @totals = {}
        @lead ||= {}
        return
      end

      deals = visible_deals
      today = Date.current
      @stale = deals.select { |deal| stale_deal?(deal) }
      @due = deals.select { |deal| deal.next_action_on == today }
      @overdue = deals.select { |deal| deal.next_action_on.present? && deal.next_action_on < today }
      @my_open_deals = deals.select { |deal| deal.owner_id == User.current.id }
      @recent_activities = recent_activities
      @totals = crm_money? ? dashboard_totals(deals) : {}
      @lead ||= {}
    end

    def visible_accounts
      return CrmAccount.none unless defined?(CrmAccount)

      CrmAccount.visible(User.current).order("#{CrmAccount.table_name}.name ASC, #{CrmAccount.table_name}.id ASC")
    end

    def visible_contacts
      return CrmContact.none unless defined?(CrmContact)

      CrmContact.visible(User.current).order("#{CrmContact.table_name}.first_name ASC, #{CrmContact.table_name}.last_name ASC, #{CrmContact.table_name}.id ASC")
    end

    def recent_activities
      return [] unless defined?(CrmActivity)

      table = CrmActivity.table_name
      visible_activities.
        order(Arel.sql("COALESCE(#{table}.occurred_at, #{table}.created_on) DESC, #{table}.id DESC")).
        limit(10).
        to_a
    end


    def visible_deals
      return CrmDeal.none unless defined?(CrmDeal)

      scope = CrmDeal.visible(User.current)
      scope = scope.joins(:stage).where(:crm_pipeline_stages => {:kind => 'open'})
      scope.to_a
    rescue ActiveRecord::StatementInvalid
      CrmDeal.visible(User.current).to_a
    end

    def visible_activities
      return CrmActivity.none unless defined?(CrmActivity)

      CrmActivity.visible(User.current)
    end

    def stale_deal?(deal)
      return false unless deal.respond_to?(:stage) && deal.stage && deal.stage.kind.to_s == 'open'

      recent_cutoff = 14.days.ago
      recent = deal.activities.where("COALESCE(#{CrmActivity.table_name}.occurred_at, #{CrmActivity.table_name}.created_on) >= ?", recent_cutoff).exists?
      future_action = deal.next_action_on.present? && deal.next_action_on > Date.current
      !recent && !future_action
    end

    def dashboard_totals(deals)
      deals.each_with_object({}) do |deal, totals|
        currency = deal.currency.to_s.presence || 'USD'
        totals[currency] ||= {:open_cents => 0, :weighted_cents => 0}
        totals[currency][:open_cents] += deal.amount_cents.to_i if deal.amount_cents
        if deal.respond_to?(:weighted_cents)
          weighted = deal.weighted_cents
          totals[currency][:weighted_cents] += weighted.to_i if weighted
        elsif deal.amount_cents
          probability = deal.respond_to?(:probability) && deal.probability
          probability ||= deal.stage.respond_to?(:probability) ? deal.stage.probability : 0
          totals[currency][:weighted_cents] += (deal.amount_cents.to_i * probability.to_i / 100)
        end
      end
    end
  end
end
