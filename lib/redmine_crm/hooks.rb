# frozen_string_literal: true

module RedmineCrm
  # Projects and issues may reference CRM records; the hooks render a reference only when
  # the current user can see the target under Crm::Access (design: Domain model → Links).
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_projects_show_right, :partial => 'crm/hooks/project_account'
    render_on :view_issues_show_details_bottom, :partial => 'crm/hooks/issue_links'

    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller && controller.class.name.start_with?('Crm::')
      stylesheet_link_tag('crm', :plugin => 'redmine_crm')
    end
  end
end
