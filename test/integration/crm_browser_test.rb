# frozen_string_literal: true

require_relative '../test_helper'

class CrmBrowserIntegrationTest < Redmine::IntegrationTest
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities

  def json_headers(csrf = nil)
    headers = {
      'CONTENT_TYPE' => 'application/json',
      'ACCEPT' => 'application/json'
    }
    headers['X-CSRF-Token'] = csrf if csrf
    headers
  end

  def csrf_token_from(body)
    body[/<meta[^>]+name=["']csrf-token["'][^>]+content=["']([^"']+)["']/i, 1]
  end

  def test_browser_patch_returns_conflict_for_a_stale_lock_version
    old_forgery_setting = ActionController::Base.allow_forgery_protection
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    ActionController::Base.allow_forgery_protection = true
    deal = CrmDeal.find(1)
    stale_version = deal.lock_version
    deal.update!(:name => 'Changed in another browser')

    get "/crm/deals/#{deal.id}"
    assert_response :success
    token = csrf_token_from(response.body)
    assert token.present?, 'the Redmine base layout must expose a csrf-token meta tag'

    patch "/crm/deals/#{deal.id}",
          :params => JSON.generate(:crm_deal => {:name => 'Stale browser edit', :lock_version => stale_version}),
          :headers => json_headers(token)
    assert_response :conflict
    assert_equal 'Changed in another browser', CrmDeal.find(1).name
  ensure
    ActionController::Base.allow_forgery_protection = old_forgery_setting
  end

  def test_browser_json_patch_requires_csrf_while_api_key_put_remains_available
    old_forgery_setting = ActionController::Base.allow_forgery_protection
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    ActionController::Base.allow_forgery_protection = true
    deal = CrmDeal.find(1)

    patch "/crm/deals/#{deal.id}",
          :params => JSON.generate(:crm_deal => {:name => 'Missing CSRF edit', :lock_version => deal.lock_version}),
          :headers => json_headers
    assert_includes [403, 422], response.status
    assert_equal 'Acme renewal', CrmDeal.find(1).name

    with_settings(:rest_api_enabled => '1') do
      put "/crm/deals/#{deal.id}.json",
          :params => {:crm_deal => {:name => 'API key edit', :lock_version => deal.lock_version}},
          :headers => crm_api_headers(staff)
      assert_includes [200, 204], response.status
      assert_equal 'API key edit', CrmDeal.find(1).name
    end
  ensure
    ActionController::Base.allow_forgery_protection = old_forgery_setting
  end
end
