# frozen_string_literal: true

require_relative '../test_helper'

class CrmAccessVisibilityTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_account_projects

  def test_staff_sees_all_active_records_and_money
    user = crm_staff_user

    assert_equal [1, 2], CrmAccount.visible(user).order(:id).pluck(:id)
    assert_equal [1, 2, 3], CrmActivity.visible(user).order(:id).pluck(:id)
    assert Crm::Access.staff?(user)
    assert Crm::Access.can_view_money?(user)
  end

  def test_viewer_sees_all_active_records_but_not_money
    user = crm_viewer_user

    assert_equal [1, 2], CrmAccount.visible(user).order(:id).pluck(:id)
    assert_equal [1, 2, 3], CrmContact.visible(user).order(:id).pluck(:id)
    assert Crm::Access.viewer?(user)
    refute Crm::Access.can_view_money?(user)
  end

  def test_contractor_is_limited_to_the_one_enabled_linked_project
    user = crm_contractor_user(1)

    assert_equal [1], CrmAccount.visible(user).order(:id).pluck(:id)
    assert_equal [1], CrmContact.visible(user).order(:id).pluck(:id)
    assert_equal [1], CrmActivity.visible(user).order(:id).pluck(:id)
    assert_empty CrmDeal.visible(user).to_a
    refute Crm::Access.can_view_money?(user)
    assert Crm::Access.contractor?(user)
  end

  def test_contractor_with_crm_module_disabled_has_no_scope
    user = crm_contractor_user(1)
    EnabledModule.where(:project_id => 1, :name => 'crm').delete_all

    assert_empty CrmAccount.visible(user).to_a
    assert_empty CrmContact.visible(user).to_a
    assert_empty CrmActivity.visible(user).to_a
    refute Crm::Access.contractor?(user)
  end

  def test_engineer_has_no_crm_visibility_even_when_a_project_member
    user = crm_engineer_user

    assert Member.where(:user_id => user.id, :project_id => 1).exists?
    assert_empty CrmAccount.visible(user).to_a
    assert_empty CrmContact.visible(user).to_a
    assert_empty CrmDeal.visible(user).to_a
    assert_equal :none, Crm::Access.capability(user)
  end

  def test_anonymous_and_non_member_have_no_crm_visibility
    anonymous = User.anonymous
    non_member = crm_non_member_user
    assert Role.find_by!(:name => 'Non member').builtin?
    assert_not Member.where(:user_id => non_member.id, :project_id => 1).exists?

    assert_empty CrmAccount.visible(anonymous).to_a
    assert_empty CrmAccount.visible(non_member).to_a
    assert_equal :none, Crm::Access.capability(anonymous)
    assert_equal :none, Crm::Access.capability(non_member)
  end
end
