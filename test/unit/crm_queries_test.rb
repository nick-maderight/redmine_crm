# frozen_string_literal: true

require_relative '../test_helper'

class CrmQueryVisibilityTest < ActiveSupport::TestCase
  fixtures :users, :groups_users, :roles, :members, :member_roles, :projects, :enabled_modules,
           :crm_pipelines, :crm_pipeline_stages, :crm_accounts, :crm_contacts,
           :crm_deals, :crm_activities, :crm_changes

  def test_money_columns_are_available_only_to_staff
    crm_with_user(crm_staff_user) do
      columns = crm_column_names(CrmDealQuery.new)
      assert_includes columns, 'amount_cents'
      assert_includes columns, 'currency'
      assert columns.any? {|name| name.include?('weighted') }
    end

    crm_with_user(crm_viewer_user) do
      columns = crm_column_names(CrmDealQuery.new)
      refute_includes columns, 'amount_cents'
      refute_includes columns, 'currency'
      refute columns.any? {|name| name.include?('weighted') }
    end
  end

  def test_hidden_custom_field_is_absent_from_viewer_filters_and_columns
    field = crm_hidden_deal_field
    crm_custom_field_value(field, CrmDeal.find(1), 'secret')

    crm_with_user(crm_viewer_user) do
      query = CrmDealQuery.new
      refute query.available_filters.key?("cf_#{field.id}")
      refute crm_column_names(query).any? {|name| name.include?(field.name) || name == "cf_#{field.id}" }
    end

    crm_with_user(User.find(1)) do
      query = CrmDealQuery.new
      assert query.available_filters.key?("cf_#{field.id}")
      assert crm_column_names(query).any? {|name| name.include?(field.name) || name == "cf_#{field.id}" }
    end
  end
end
