# frozen_string_literal: true

require_relative '../../test_helper'

class Redmine::ApiTest::CrmApiTest < Redmine::ApiTest::Base
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_changes, :crm_account_projects

  def record_payload(json, key)
    json[key] || json
  end

  def changes_payload(json, key = 'deal')
    record = record_payload(json, key)
    record['changes'] || json['changes'] || []
  end

  def test_money_is_present_for_staff_but_absent_from_viewer_json_and_history_values
    get '/crm/deals/1.json?include=changes', :headers => crm_api_headers(crm_staff_user)
    assert_response :success, response.body
    staff_json = crm_json_response
    staff_deal = record_payload(staff_json, 'deal')
    assert_equal 100000, staff_deal['amount_cents']
    assert_equal 'USD', staff_deal['currency']
    staff_money_change = changes_payload(staff_json).find {|row| row['prop_key'] == 'amount_cents' }
    assert staff_money_change
    assert_equal '100000', staff_money_change['value']

    get '/crm/deals/1.json?include=changes', :headers => crm_api_headers(crm_viewer_user)
    assert_response :success
    viewer_json = crm_json_response
    viewer_deal = record_payload(viewer_json, 'deal')
    refute viewer_deal.key?('amount_cents')
    refute viewer_deal.key?('currency')
    viewer_money_change = changes_payload(viewer_json).find {|row| row['prop_key'] == 'amount_cents' }
    if viewer_money_change
      refute_equal '90000', viewer_money_change['old_value']
      refute_equal '100000', viewer_money_change['value']
    end
  end

  def test_api_put_returns_conflict_for_a_stale_lock_version
    key = crm_staff_user
    deal = CrmDeal.find(1)
    stale_version = deal.lock_version

    put '/crm/deals/1.json',
        :params => {:name => 'First API edit', :lock_version => stale_version},
        :headers => crm_api_headers(key)
    assert_includes [200, 204], response.status, response.body

    put '/crm/deals/1.json',
        :params => {:name => 'Stale API edit', :lock_version => stale_version},
        :headers => crm_api_headers(key)
    assert_response :conflict
    assert_equal 'First API edit', CrmDeal.find(1).name
  end

  def test_duplicate_activity_external_identity_returns_the_existing_row
    feed = crm_feed_user
    assert_no_difference('CrmActivity.count') do
      post '/crm/feed/activities.json',
           :params => {
             :kind => 'message', :channel => 'upwork', :direction => 'inbound',
             :subject => 'Replay', :body => 'Replay body',
             :occurred_at => '2026-01-02T12:00:00Z',
             :external_source => 'upwork', :external_id => 'room-1-message-1',
             :account_id => 1, :contact_id => 1, :deal_id => 1
           },
           :headers => crm_api_headers(feed)
    end
    assert_equal 200, response.status, response.body
    assert_equal 1, record_payload(crm_json_response, 'activity')['id']
  end

  def test_feed_cannot_use_a_collection_endpoint
    get '/crm/accounts.json', :headers => crm_api_headers(crm_feed_user)
    assert_response :forbidden
  end

  def test_feed_lookup_follows_a_merged_contact_to_the_survivor
    source = CrmContact.create!(:first_name => 'Merged', :last_name => 'Source', :email => 'merged-source@example',
                                :external_ref => 'feed:merged-source')
    target = CrmContact.create!(:first_name => 'Merged', :last_name => 'Target', :email => 'merged-target@example',
                                :external_ref => 'feed:merged-target')
    source.update_columns(:merged_into_id => target.id, :archived_on => Time.current)

    get '/crm/contacts/lookup.json', :params => {:external_ref => source.external_ref},
        :headers => crm_api_headers(crm_feed_user)
    assert_response :success, response.body
    assert_equal target.id, record_payload(crm_json_response, 'contact')['id']
  end

  def test_feed_accepts_activity_on_a_plain_archived_parent
    before_count = CrmActivity.count
    post '/crm/feed/activities.json',
         :params => {
           :crm_activity => {
             :kind => 'message', :channel => 'upwork', :direction => 'inbound',
             :occurred_at => '2026-01-05T12:00:00Z',
             :body => 'Late activity for an archived account',
             :external_source => 'upwork', :external_id => 'archived-accepted-1',
             :account_id => 3
           }
         },
         :headers => crm_api_headers(crm_feed_user)
    assert_response :success, response.body
    assert_equal before_count + 1, CrmActivity.count, response.body
    assert_equal 3, CrmActivity.order(:id).last.account_id
  end

  def test_feed_rejects_activity_on_a_merged_parent
    source = CrmAccount.create!(:name => 'Feed merged source', :domain => 'feed-merged-source.example', :status => 'lead')
    target = CrmAccount.create!(:name => 'Feed merged target', :domain => 'feed-merged-target.example', :status => 'lead')
    source.update_columns(:merged_into_id => target.id, :archived_on => Time.current)

    post '/crm/feed/activities.json',
         :params => {
           :crm_activity => {
             :kind => 'message', :channel => 'upwork', :direction => 'inbound',
             :occurred_at => '2026-01-05T12:01:00Z',
             :body => 'Must not attach to merged account',
             :external_source => 'upwork', :external_id => 'merged-rejected-1',
             :account_id => source.id
           }
         },
         :headers => crm_api_headers(crm_feed_user)
    assert_includes [403, 422], response.status, response.body
  end

  def test_contractor_api_is_forbidden_even_for_a_linked_account
    contractor = crm_contractor_user(1)

    get '/crm/accounts.json', :headers => crm_api_headers(contractor)
    assert_response :forbidden
    get '/crm/deals/1.json', :headers => crm_api_headers(contractor)
    assert_response :forbidden
  end

  def test_restore_name_and_domain_collisions_return_conflict
    account = CrmAccount.find(3)
    account.update_columns(:name => CrmAccount.find(1).name, :domain => 'restored.example')
    put '/crm/accounts/3/restore.json',
        :params => {:crm_account => {:lock_version => account.lock_version}, :lock_version => account.lock_version},
        :headers => crm_api_headers(crm_staff_user)
    assert_includes [409, 422], response.status, response.body
    assert account.reload.archived?

    account.update_columns(:name => 'Restorable again', :domain => CrmAccount.find(1).domain)
    put '/crm/accounts/3/restore.json',
        :params => {:crm_account => {:lock_version => account.lock_version}, :lock_version => account.lock_version},
        :headers => crm_api_headers(crm_staff_user)
    assert_includes [409, 422], response.status, response.body
    assert account.reload.archived?
  end

  def test_restore_email_collision_returns_conflict
    contact = CrmContact.find(4)
    contact.update_columns(:email => CrmContact.find(1).email)
    put '/crm/contacts/4/restore.json',
        :params => {:crm_contact => {:lock_version => contact.lock_version}, :lock_version => contact.lock_version},
        :headers => crm_api_headers(crm_staff_user)
    assert_includes [409, 422], response.status, response.body
  end

  def test_hidden_custom_field_is_absent_from_non_admin_history_json
    field = crm_hidden_deal_field('API hidden field')
    crm_custom_field_value(field, CrmDeal.find(1), 'do not disclose')
    CrmChange.create!(:record_type => 'CrmDeal', :record_id => 1, :user_id => 3,
                      :prop_key => "cf_#{field.id}", :old_value => 'old hidden', :value => 'do not disclose',
                      :created_on => Time.current)

    get '/crm/deals/1.json?include=changes', :headers => crm_api_headers(crm_viewer_user)
    assert_response :success, response.body
    assert_not_includes response.body, 'API hidden field'
    assert_not_includes response.body, 'do not disclose'
    assert_not_includes response.body, 'old hidden'
  end
end
