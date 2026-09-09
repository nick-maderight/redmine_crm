# frozen_string_literal: true

require File.expand_path('lib/redmine_crm', __dir__)

Redmine::Plugin.register :redmine_crm do
  name 'Made Right CRM'
  author 'Made Right Software'
  description 'Accounts, contacts, deals and an activity timeline as a Redmine plugin. Not a project.'
  version '0.1.0'
  url 'https://github.com/nick-maderight/redmine_crm'

  requires_redmine :version => '7.0'..'7.9'

  settings :default => {'feed_contract_version' => nil, 'feed_last_success_at' => nil}

  project_module :crm do
    permission :view_crm_linked, {}, :read => true
  end

  menu :top_menu, :crm,
       {:controller => 'crm/dashboard', :action => 'index'},
       :caption => :label_crm,
       :if => proc { Crm::Access.staff_or_viewer_or_linked?(User.current) },
       :after => :projects
end

RedmineCrm.setup!
