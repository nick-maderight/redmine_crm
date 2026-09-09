# frozen_string_literal: true

require_relative '../test_helper'

class CrmBrowserIntegrationTest < Redmine::IntegrationTest
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities

  def json_headers(csrf = nil)
    headers = {
      'CONTENT_TYPE' => 'application/json',
      'ACCEPT' => 'application/json',
      'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
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
  def assert_redirect_to_path(path)
    assert_response :redirect
    assert_equal path, response.location.sub(%r{\Ahttps?://[^/]+}, '')
    follow_redirect!
    assert_response :success
  end

  def test_html_timeline_activity_create_redirects_to_deal_with_flash
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    body = 'Browser timeline mutation test'

    post '/crm/activities', :params => {
      :activity => {
        :deal_id => 1, :kind => 'note', :occurred_at => '2026-09-09T16:20', :body => body
      },
      :back_url => '/crm/deals/1'
    }

    assert_redirect_to_path '/crm/deals/1'
    assert_select 'div.flash.notice', :text => /Created successfully/
    assert CrmActivity.where(:body => body, :deal_id => 1).exists?
  end

  def test_html_stage_move_redirects_with_flash_and_rejects_stale_lock
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    deal = CrmDeal.find(1)
    target_stage = CrmPipelineStage.find(2)
    current_version = deal.lock_version

    put '/crm/deals/1/move', :params => {
      :deal => {:stage_id => target_stage.id, :lock_version => current_version},
      :back_url => '/crm/deals/1'
    }
    assert_redirect_to_path '/crm/deals/1'
    assert_select 'div.flash.notice', :text => /Updated successfully/
    assert_equal target_stage.id, CrmDeal.find(1).stage_id

    stale_version = CrmDeal.find(1).lock_version
    CrmDeal.find(1).update!(:name => 'Changed before stage retry')
    put '/crm/deals/1/move', :params => {
      :deal => {:stage_id => 3, :lock_version => stale_version},
      :back_url => '/crm/deals/1'
    }
    assert_redirect_to_path '/crm/deals/1'
    assert_select 'div.flash.error', :text => /updated by another user/i
    assert_equal target_stage.id, CrmDeal.find(1).stage_id
  end

  def test_html_bulk_ids_owner_stage_archive_restore_redirect_and_summarize
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    ids = [1, 2]

    post '/crm/deals/bulk', :params => {:ids => ids, :attributes => {:owner_id => 1}, :back_url => '/crm/deals'}
    assert_redirect_to_path '/crm/deals'
    assert_select 'div.flash.notice', :text => /2 deals updated/
    assert_equal [1, 1], CrmDeal.where(:id => ids).order(:id).pluck(:owner_id)

    post '/crm/deals/bulk', :params => {:ids => ids, :attributes => {:stage_id => 2}, :back_url => '/crm/deals'}
    assert_redirect_to_path '/crm/deals'
    assert_select 'div.flash.notice', :text => /2 deals updated/
    assert_equal [2, 2], CrmDeal.where(:id => ids).order(:id).pluck(:stage_id)

    post '/crm/deals/bulk', :params => {:ids => ids, :bulk_action => 'archive', :back_url => '/crm/deals'}
    assert_redirect_to_path '/crm/deals'
    assert_select 'div.flash.notice', :text => /2 deals updated/
    assert_equal 2, CrmDeal.where(:id => ids).where.not(:archived_on => nil).count

    post '/crm/deals/bulk', :params => {:ids => ids, :bulk_action => 'restore', :back_url => '/crm/deals'}
    assert_redirect_to_path '/crm/deals'
    assert_select 'div.flash.notice', :text => /2 deals updated/
    assert_equal 0, CrmDeal.where(:id => ids).where.not(:archived_on => nil).count
  end

  def test_browser_xhr_json_move_remains_json
    staff = crm_staff_user
    log_user(staff.login, 'foo')
    deal = CrmDeal.find(1)
    headers = json_headers
    headers['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest'

    put '/crm/deals/1/move',
        :params => JSON.generate(:deal => {:stage_id => 2, :lock_version => deal.lock_version}),
        :headers => headers

    assert_response :success
    payload = crm_json_response
    assert_equal 1, payload['id']
    assert payload.key?('record')
  end
end
