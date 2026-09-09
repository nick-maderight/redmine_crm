# frozen_string_literal: true

module Crm
  class AccountProjectsController < BaseController
    before_action :require_staff
    accept_api_auth :create, :destroy

    def create

      account = CrmAccount.visible(User.current).find(params[:id])
      project_id = params[:project_id] || params.dig(:account_project, :project_id)
      project = Project.find(project_id)
      bridge = CrmAccountProject.find_by(:account_id => account.id, :project_id => project.id)
      created = false
      unless bridge
        bridge = CrmAccountProject.new(:account_id => account.id, :project_id => project.id)
        unless bridge.save
          return render_bridge_error(bridge)
        end
        created = true
        account.crm_change!('link_project', nil, project.id.to_s, User.current) if account.respond_to?(:crm_change!)
      end
      respond_to do |format|
        format.html { redirect_to crm_account_path(account) }
        format.api { render :json => bridge_payload(bridge), :status => created ? :created : :ok }
        format.json { render :json => bridge_payload(bridge), :status => created ? :created : :ok }
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    rescue ActiveRecord::RecordNotUnique
      bridge = CrmAccountProject.find_by(:account_id => account.id, :project_id => project.id)
      respond_to do |format|
        format.api { render :json => bridge_payload(bridge), :status => :ok }
        format.json { render :json => bridge_payload(bridge), :status => :ok }
        format.html { redirect_to crm_account_path(account) }
      end
    end

    def destroy
      return head(:forbidden) unless Crm::Access.staff?(User.current)

      account = CrmAccount.visible(User.current).find(params[:id])
      project_id = params[:project_id]
      bridge = CrmAccountProject.find_by!(:account_id => account.id, :project_id => project_id)
      bridge.destroy!
      account.crm_change!('link_project', project_id.to_s, nil, User.current) if account.respond_to?(:crm_change!)
      respond_to do |format|
        format.html { redirect_to crm_account_path(account) }
        format.api { render :json => {:account_id => account.id, :project_id => project_id.to_i, :deleted => true}, :status => :ok }
        format.json { render :json => {:account_id => account.id, :project_id => project_id.to_i, :deleted => true}, :status => :ok }
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    private

    def bridge_payload(bridge)
      {:account_id => bridge.account_id, :project_id => bridge.project_id}
    end

    def render_bridge_error(bridge)
      respond_to do |format|
        format.html { render :plain => bridge.errors.full_messages.join(', '), :status => :unprocessable_content }
        format.api { render :json => {:errors => bridge.errors.full_messages}, :status => :unprocessable_content }
        format.json { render :json => {:errors => bridge.errors.full_messages}, :status => :unprocessable_content }
      end
    end
  end
end
