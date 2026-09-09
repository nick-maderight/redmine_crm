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
      deal = result.respond_to?(:deal) ? result.deal : result
      if deal.respond_to?(:persisted?) && deal.persisted?
        respond_to do |format|
          format.html { redirect_to crm_deal_path(deal) }
          format.json { render :json => {:id => deal.id, :deal_id => deal.id}, :status => :created }
        end
      else
        @lead = result
        prepare_dashboard
        render :index, :status => :unprocessable_content
      end
    rescue ActiveRecord::RecordInvalid => e
      @lead = e.respond_to?(:record) ? e.record : payload
      prepare_dashboard
      render :index, :status => :unprocessable_content
    rescue ActiveRecord::RecordNotUnique
      @lead = payload
      prepare_dashboard
      render :index, :status => :unprocessable_content
    end

    private

    def prepare_dashboard
      deals = visible_deals
      today = Date.current
      @stale = deals.select { |deal| stale_deal?(deal) }
      @due = deals.select { |deal| deal.next_action_on == today }
      @overdue = deals.select { |deal| deal.next_action_on.present? && deal.next_action_on < today }
      @my_open_deals = deals.select { |deal| deal.owner_id == User.current.id }
      @recent_activities = visible_activities.order(Arel.sql('COALESCE(occurred_at, created_on) DESC'), :id => :desc).limit(10).to_a
      @totals = crm_money? ? dashboard_totals(deals) : {}
      @lead ||= {}
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
      recent = deal.activities.where('COALESCE(occurred_at, created_on) >= ?', recent_cutoff).exists?
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
