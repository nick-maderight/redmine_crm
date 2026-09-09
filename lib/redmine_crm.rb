# frozen_string_literal: true

module RedmineCrm
  VERSION = '0.1.0'

  # Group names are exact and case-sensitive (design: Access control → Authorization sources).
  GROUP_STAFF  = 'crm-staff'
  GROUP_VIEWER = 'crm-viewer'
  GROUP_FEED   = 'crm-feed'
  CONTRACTOR_ROLE_NAME = 'CRM Contractor'
  SEARCH_TYPES = %w(crm_accounts crm_contacts crm_deals crm_activities).freeze

  def self.setup!
    adapter = ActiveRecord::Base.connection_db_config.adapter.to_s
    unless adapter =~ /postgres/i
      raise Redmine::PluginRequirementError, "redmine_crm requires PostgreSQL (adapter is #{adapter})"
    end
    require_relative 'crm/access'
    require_relative 'redmine_crm/hooks'
    require_relative 'redmine_crm/custom_fields_tabs'
    RedmineCrm::CustomFieldsTabs.register!
    SEARCH_TYPES.each { |t| Redmine::Search.register t }
  end
end
