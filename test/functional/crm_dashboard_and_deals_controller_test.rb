# frozen_string_literal: true

require_relative '../test_helper'

class CrmDashboardControllerTest < Redmine::ControllerTest
  tests Crm::DashboardController

  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_account_projects

  def test_contractor_dashboard_lists_only_linked_records
    contractor = crm_contractor_user
    @request.session[:user_id] = contractor.id

    get :index

    assert_response :success
    assert_select 'h3', :text => /CRM accounts/
    assert_select 'h3', :text => /CRM contacts/
    assert_select 'a', :text => /Acme Corporation/
    assert_select 'a', :text => /Alice Acme/
    assert_select 'a', :text => /Acme message/
    assert_no_match(/Acme renewal/, response.body)
    assert_no_match(/Pipeline totals|Open total|Weighted total|New lead/, response.body)
  end
end

class CrmDealsControllerTest < Redmine::ControllerTest
  tests Crm::DealsController

  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_account_projects

  def test_contractor_deal_browser_routes_are_not_found
    contractor = crm_contractor_user
    @request.session[:user_id] = contractor.id

    get :index
    assert_equal 404, response.status

    get :show, :params => {:id => 1}
    assert_equal 404, response.status

    get :board
    assert_equal 404, response.status

    put :move, :params => {:id => 1, :stage_id => 1, :lock_version => 0}
    assert_equal 404, response.status
  end

  def test_contractor_deal_api_route_remains_forbidden
    contractor = crm_contractor_user
    @request.session[:user_id] = contractor.id

    get :index, :params => {:format => 'json'}

    assert_equal 403, response.status
  end
end
