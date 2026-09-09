# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__)

plugin_fixture_path = File.expand_path('fixtures', __dir__)
unless ActiveSupport::TestCase.fixture_paths.include?(plugin_fixture_path)
  ActiveSupport::TestCase.fixture_paths = ActiveSupport::TestCase.fixture_paths + [plugin_fixture_path]
end

[Redmine::IntegrationTest, Redmine::ApiTest::Base].each do |test_class|
  next unless test_class.respond_to?(:fixture_paths)
  unless test_class.fixture_paths.include?(plugin_fixture_path)
    test_class.fixture_paths = test_class.fixture_paths + [plugin_fixture_path]
  end
end

# Shared setup for the plugin's unit, controller and integration tests.  The
# Redmine fixtures remain the source of truth for users, projects, memberships
# and builtin roles; CRM-specific rows live in this plugin's fixture directory.
module CrmTestSupport
  def crm_group(name)
    Group.where(:lastname => name, :type => 'Group').first_or_create!
  end

  def crm_grant_group(user, name)
    group = crm_group(name)
    group.users << user unless group.users.exists?(user.id)
    group
  end

  def crm_staff_user
    user = User.find(3)
    crm_grant_group(user, 'crm-staff')
    user
  end

  def crm_viewer_user
    user = User.find(4)
    crm_grant_group(user, 'crm-viewer')
    user
  end

  def crm_feed_user
    user = User.find(8)
    crm_grant_group(user, 'crm-feed')
    user
  end

  def crm_engineer_user
    User.find(2)
  end

  def crm_non_member_user
    User.find(7)
  end

  def crm_contractor_role
    role = Role.where(:name => RedmineCrm::CONTRACTOR_ROLE_NAME, :builtin => 0).first_or_initialize
    permissions = Array(role.permissions).map(&:to_sym)
    role.permissions = (permissions | [:view_crm_linked])
    role.save!
    role
  end

  def crm_enable_project(project_id)
    EnabledModule.where(:project_id => project_id, :name => 'crm').first_or_create!
  end

  def crm_grant_contractor(user, project_id = 1)
    crm_enable_project(project_id)
    role = crm_contractor_role
    member = Member.where(:project_id => project_id, :user_id => user.id).first
    if member
      member.member_roles.where(:role_id => role.id).first_or_create!(:role => role)
    else
      member = Member.create!(:project_id => project_id, :user_id => user.id, :role_ids => [role.id])
    end
    member
  end

  def crm_contractor_user(project_id = 1)
    user = crm_non_member_user
    crm_grant_contractor(user, project_id)
    user
  end

  def crm_with_user(user)
    previous = User.current
    User.current = user
    yield
  ensure
    User.current = previous
  end

  def crm_api_headers(user, content_type = nil)
    headers = {
      'X-Redmine-API-Key' => user.api_key,
      'ACCEPT' => 'application/json'
    }
    headers['CONTENT_TYPE'] = content_type if content_type
    headers
  end

  def crm_json_response
    ActiveSupport::JSON.decode(response.body)
  end

  def crm_column_names(query)
    query.available_columns.map do |column|
      column.respond_to?(:name) ? column.name.to_s : column.to_s
    end
  end

  def crm_custom_field_value(field, record, value)
    CustomValue.create!(
      :custom_field_id => field.id,
      :customized_type => record.class.base_class.name,
      :customized_id => record.id,
      :value => value
    )
  end

  def crm_hidden_deal_field(name = 'Private forecast')
    CrmDealCustomField.create!(
      :name => name,
      :field_format => 'string',
      :is_for_all => true,
      :is_filter => true,
      :is_required => false,
      :visible => false
    )
  end

  def crm_assert_no_money(payload)
    serialized = payload.to_json
    refute_match(/amount_cents|weighted_cents|currency|open_cents/i, serialized)
  end
end

ActiveSupport::TestCase.setup do
  Crm::Access.reset! if defined?(Crm::Access)
end

ActiveSupport::TestCase.teardown do
  Crm::Access.reset! if defined?(Crm::Access)
end

ActiveSupport::TestCase.include(CrmTestSupport)
