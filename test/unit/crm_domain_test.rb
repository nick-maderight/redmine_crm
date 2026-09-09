# frozen_string_literal: true

require_relative '../test_helper'

class CrmDomainTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_account_projects, :crm_changes

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

  def test_account_create_writes_one_created_change_and_update_writes_each_changed_field
    account = CrmAccount.create!(
      :name => 'Audit Noise Account',
      :domain => 'audit-noise.example',
      :status => 'lead'
    )

    changes = CrmChange.where(:record_type => 'CrmAccount', :record_id => account.id).order(:id)
    assert_equal 1, changes.count
    assert_equal 'created', changes.first.prop_key
    assert_nil changes.first.old_value
    assert_equal account.name, changes.first.value

    account.update!(:name => 'Audit Noise Renamed', :phone => '+1 555 0199')

    changes = CrmChange.where(:record_type => 'CrmAccount', :record_id => account.id).order(:id)
    assert_equal 3, changes.count
    assert_equal %w[created name phone], changes.map(&:prop_key)
  end

  def test_account_custom_field_update_writes_one_custom_change
    field = CrmAccountCustomField.create!(
      :name => 'Audit Custom Field',
      :field_format => 'string',
      :is_for_all => true,
      :is_filter => true,
      :visible => true
    )
    account = CrmAccount.new(
      :name => 'Audit Custom Account',
      :domain => 'audit-custom.example',
      :status => 'lead'
    )
    account.custom_field_values = {field.id.to_s => 'before'}
    account.save!
    changes_before = CrmChange.where(:record_type => 'CrmAccount', :record_id => account.id).count
    assert_equal 1, changes_before

    account.custom_field_values = {field.id.to_s => 'after'}
    account.save!

    changes = CrmChange.where(
      :record_type => 'CrmAccount', :record_id => account.id, :prop_key => "cf_#{field.id}"
    )
    assert_equal 1, changes.count
    assert_equal changes_before + 1, CrmChange.where(:record_type => 'CrmAccount', :record_id => account.id).count
    assert_equal 'before', changes.first.old_value
    assert_equal 'after', changes.first.value
  end

  def test_imported_create_writes_one_imported_change_with_source_reference
    account = CrmAccount.new(
      :name => 'Imported Audit Account',
      :domain => 'imported-audit.example',
      :status => 'lead',
      :external_ref => 'twenty:audit-account'
    )
    account.crm_audit_context = 'imported'
    account.crm_audit_source_ref = account.external_ref
    account.save!

    changes = CrmChange.where(:record_type => 'CrmAccount', :record_id => account.id)
    assert_equal 1, changes.count
    assert_equal 'imported', changes.first.prop_key
    assert_equal account.external_ref, changes.first.value
  end
end
