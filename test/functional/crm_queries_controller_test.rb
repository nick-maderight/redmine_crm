# frozen_string_literal: true

require_relative '../test_helper'

class CrmQueriesControllerTest < Redmine::ControllerTest
  tests Crm::QueriesController

  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities

  def test_staff_can_save_a_global_crm_query
    staff = crm_staff_user
    @request.session[:user_id] = staff.id

    post :create, :params => {
      :type => 'CrmDealQuery',
      :query_is_for_all => '1',
      :query => {
        :name => 'Staff pipeline view',
        :description => 'Saved by CRM staff',
        :visibility => Query::VISIBILITY_PUBLIC,
        :column_names => ['subject']
      }
    }

    assert_response :redirect
    query = Query.find_by(:name => 'Staff pipeline view')
    assert query
    assert_equal 'CrmDealQuery', query.type
    assert_nil query.project_id
  end

  def test_viewer_cannot_save_a_crm_query
    @request.session[:user_id] = crm_viewer_user.id

    post :create, :params => {
      :type => 'CrmDealQuery',
      :query_is_for_all => '1',
      :query => {:name => 'Viewer must not save'}
    }

    assert_response :forbidden
    assert_nil Query.find_by(:name => 'Viewer must not save')
  end
end
