# frozen_string_literal: true

require_relative '../test_helper'

class CrmDomainTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_account_projects

  def test_composite_pipeline_stage_foreign_key_rejects_a_stage_from_another_pipeline
    deal = CrmDeal.find(1)

    assert_raises(ActiveRecord::StatementInvalid) do
      CrmDeal.transaction(:requires_new => true) do
        deal.update_columns(:stage_id => 10)
      end
    end
    assert_equal 1, deal.reload.stage_id
    assert_equal 1, deal.pipeline_id
  end

  def test_restore_rejects_active_account_name_collision
    archived = CrmAccount.find(3)
    archived.update_columns(:name => CrmAccount.find(1).name, :domain => 'restored.example')

    assert_raises(ActiveRecord::RecordInvalid) { archived.restore!(crm_staff_user) }
    assert archived.reload.archived?
  end

  def test_restore_rejects_active_account_domain_collision
    archived = CrmAccount.find(3)
    archived.update_columns(:name => 'Restorable Account', :domain => CrmAccount.find(1).domain)

    assert_raises(ActiveRecord::RecordInvalid) { archived.restore!(crm_staff_user) }
    assert archived.reload.archived?
  end

  def test_restore_rejects_active_contact_email_collision
    archived = CrmContact.find(4)
    archived.update_columns(:email => CrmContact.find(1).email)

    assert_raises(ActiveRecord::RecordInvalid) { archived.restore!(crm_staff_user) }
    assert archived.reload.archived?
  end

  def test_new_deal_resolves_default_pipeline_and_first_open_stage
    deal = CrmDeal.new(
      :name => 'Deal with implicit pipeline',
      :contact_id => 1,
      :owner_id => 3,
      :amount_cents => 12500
    )

    assert deal.save!, deal.errors.full_messages.to_sentence
    assert_nil deal.next_action
    assert_nil deal.next_action_on
    assert_equal 1, deal.stage_id
    assert_equal 1, deal.account_id
  end
end
