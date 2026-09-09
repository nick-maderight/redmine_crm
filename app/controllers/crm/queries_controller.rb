# frozen_string_literal: true

module Crm
  class QueriesController < BaseController
    QUERY_CLASSES = {
      'CrmAccountQuery' => CrmAccountQuery,
      'CrmContactQuery' => CrmContactQuery,
      'CrmDealQuery' => CrmDealQuery,
      'CrmActivityQuery' => CrmActivityQuery
    }.freeze

    before_action :require_crm_read
    before_action :require_query_staff, :only => [:new, :create, :edit, :update, :destroy]
    before_action :find_query, :only => [:edit, :update, :destroy]

    def new
      @query = query_class.new
      @query.user = User.current
      @query.project = nil
      @query.build_from_params(params)
      @query.visibility = Query::VISIBILITY_PUBLIC if @query.visibility.blank?
      render
    end

    def create
      @query = query_class.new
      @query.user = User.current
      @query.project = nil
      update_query_from_params

      if @query.save
        flash[:notice] = l(:notice_successful_create)
        redirect_to_items(:query_id => @query.id)
      else
        render :action => 'new', :layout => !request.xhr?
      end
    end

    def edit
      render
    end

    def update
      update_query_from_params

      if @query.save
        flash[:notice] = l(:notice_successful_update)
        redirect_to_items(:query_id => @query.id)
      else
        render :action => 'edit'
      end
    end

    def destroy
      @query.destroy
      redirect_to_items(:set_filter => 1)
    end

    private

    def require_query_staff
      return true if Crm::Access.can_manage_queries?(User.current)

      render_403
      false
    end

    def query_class
      requested = params[:type].presence || params.dig(:query, :type).presence || 'CrmDealQuery'
      QUERY_CLASSES.fetch(requested.to_s) { raise ActiveRecord::RecordNotFound }
    end

    def find_query
      requested = params[:type].presence
      if requested
        klass = QUERY_CLASSES.fetch(requested.to_s) { raise ActiveRecord::RecordNotFound }
        @query = klass.where(:project_id => nil).find(params[:id])
      else
        @query = Query.where(:project_id => nil).find(params[:id])
        unless QUERY_CLASSES.value?(@query.class)
          raise ActiveRecord::RecordNotFound
        end
      end
      raise ActiveRecord::RecordNotFound unless @query.visible?(User.current)
      @query.project = nil
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def update_query_from_params
      @query.project = nil
      @query.build_from_params(params)
      @query.column_names = nil if params[:default_columns].present?
      query_values = params[:query] || {}
      @query.sort_criteria = query_values[:sort_criteria] || @query.sort_criteria
      @query.name = query_values[:name]
      @query.description = query_values[:description]
      @query.visibility = query_values[:visibility].presence || Query::VISIBILITY_PUBLIC
      @query.role_ids = query_values[:role_ids]
      @query
    end

    def redirect_to_items(options = {})
      route = case @query.class.name
              when 'CrmAccountQuery' then crm_accounts_path(options)
              when 'CrmContactQuery' then crm_contacts_path(options)
              when 'CrmDealQuery' then crm_deals_path(options)
              when 'CrmActivityQuery' then crm_activities_path(options)
              else crm_deals_path(options)
              end
      redirect_to route
    end
  end
end
