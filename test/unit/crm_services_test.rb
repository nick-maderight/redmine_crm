# frozen_string_literal: true

require_relative '../test_helper'

class CrmMoveDealTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_changes

  def test_move_deal_atomically_writes_stage_and_next_action_changes
    deal = CrmDeal.find(1)
    stage = CrmPipelineStage.find(2)
    actor = crm_staff_user
    old_version = deal.lock_version
    stage_changes_before = CrmChange.where(
      :record_type => 'CrmDeal', :record_id => deal.id, :prop_key => 'stage'
    ).count

    Crm::MoveDeal.call(:deal => deal, :stage => stage, :user => actor, :lock_version => old_version)

    deal.reload
    assert_equal stage.id, deal.stage_id
    assert_equal stage.pipeline_id, deal.pipeline_id
    assert_equal 'Confirm requirements', deal.next_action
    assert_equal Date.current + 5, deal.next_action_on
    assert_equal stage_changes_before + 1,
                 CrmChange.where(:record_type => 'CrmDeal', :record_id => deal.id, :prop_key => 'stage').count
    assert CrmChange.where(:record_type => 'CrmDeal', :record_id => deal.id, :prop_key => 'next_action').exists?
    assert CrmChange.where(:record_type => 'CrmDeal', :record_id => deal.id, :prop_key => 'next_action_on').exists?
  end

  def test_move_deal_rejects_a_stale_lock_version_without_changing_the_stage
    deal = CrmDeal.find(1)
    old_version = deal.lock_version
    deal.update!(:name => 'Changed by another editor')

    assert_raises(ActiveRecord::StaleObjectError) do
      Crm::MoveDeal.call(
        :deal => deal.reload,
        :stage => CrmPipelineStage.find(2),
        :user => crm_staff_user,
        :lock_version => old_version
      )
    end
    assert_equal 1, deal.reload.stage_id
  end
end

class CrmMergeTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_changes

  def test_account_merge_repoints_children_and_writes_merge_changes
    source = CrmAccount.create!(:name => 'Merge Source', :domain => 'merge-source.example', :status => 'prospect')
    contact = CrmContact.create!(:account_id => source.id, :first_name => 'Moved', :last_name => 'Contact', :email => 'moved@merge-source.example')
    deal = CrmDeal.create!(:name => 'Moved deal', :account_id => source.id, :contact_id => contact.id,
                           :pipeline_id => 1, :stage_id => 1, :amount_cents => 10_000)
    activity = CrmActivity.create!(:kind => 'note', :body => 'Moved activity', :occurred_at => Time.current,
                                   :account_id => source.id, :visibility => 'staff')
    target = CrmAccount.find(1)

    Crm::Merge.call(:source => source, :target => target, :user => crm_staff_user)
    source.reload
    assert_equal target.id, source.merged_into_id
    assert source.archived?
    assert_equal target.id, contact.reload.account_id
    assert_equal target.id, deal.reload.account_id
    assert_equal target.id, activity.reload.account_id
    assert CrmChange.where(:record_type => 'CrmAccount', :record_id => source.id, :prop_key => 'merged_into').exists?
    assert CrmChange.where(:record_type => 'CrmAccount', :record_id => target.id, :prop_key => 'merged_from').exists?
  end

  def test_contact_merge_refuses_a_cross_account_closure
    source = CrmContact.find(1)
    target = CrmContact.find(2)

    assert_raises(ActiveRecord::RecordInvalid) do
      Crm::Merge.call(:source => source, :target => target, :user => crm_staff_user)
    end
    assert_nil source.reload.merged_into_id
    assert_equal 1, source.account_id
    assert_equal 2, target.reload.account_id
  end
end
