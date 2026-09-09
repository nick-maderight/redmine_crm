# frozen_string_literal: true

module RedmineCrm
  # The one additive core constant the plugin touches: the custom-field administration tabs.
  module CustomFieldsTabs
    TABS = [
      {:name => 'CrmAccountCustomField', :partial => 'custom_fields/index', :label => :label_crm_account_plural},
      {:name => 'CrmContactCustomField', :partial => 'custom_fields/index', :label => :label_crm_contact_plural},
      {:name => 'CrmDealCustomField',    :partial => 'custom_fields/index', :label => :label_crm_deal_plural}
    ].freeze

    def self.register!
      tabs = CustomFieldsHelper::CUSTOM_FIELDS_TABS
      TABS.each do |tab|
        tabs << tab unless tabs.any? { |t| t[:name] == tab[:name] }
      end
    end
  end
end
