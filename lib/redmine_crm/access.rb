# frozen_string_literal: true

# Plugin-side authorization. The CRM is not a Redmine project: staff, viewer and feed
# capabilities come from exact Redmine group membership; contractor scope comes from the
# single Redmine permission :view_crm_linked held through a 'CRM Contractor' role on a
# client-project membership whose crm module is enabled. Precedence:
# admin > crm-staff > crm-viewer > crm-feed > contractor > deny. Capabilities never union.
module Crm
  module Access
    CAPABILITIES = %i[admin staff viewer feed contractor none].freeze

    # Request-local memo (reset automatically by Rails between requests, like User.current).
    class Memo < ActiveSupport::CurrentAttributes
      attribute :group_names, :contractor_projects, :contractor_role_ids
    end

    class << self
      def group_names(user)
        return [] unless user&.logged?
        Memo.group_names ||= {}
        Memo.group_names[user.id] ||= user.groups.pluck(:lastname)
      end

      def reset!
        Memo.reset
      end

      # Highest capability branch for the user (symbol).
      def capability(user)
        return :none unless user&.logged?
        return :admin if user.admin?
        names = group_names(user)
        return :staff if names.include?(RedmineCrm::GROUP_STAFF)
        return :viewer if names.include?(RedmineCrm::GROUP_VIEWER)
        return :feed if names.include?(RedmineCrm::GROUP_FEED)
        return :contractor if contractor_project_ids(user).any?
        :none
      end

      def admin?(user)      = capability(user) == :admin
      def staff?(user)      = %i[admin staff].include?(capability(user))
      def viewer?(user)     = capability(user) == :viewer
      def feed?(user)       = capability(user) == :feed
      def contractor?(user) = capability(user) == :contractor

      # Read access to the CRM pages (staff, viewer or linked contractor).
      def staff_or_viewer_or_linked?(user)
        %i[admin staff viewer contractor].include?(capability(user))
      end

      # Anyone who may read all records (no linked-scope filtering).
      def reads_all?(user) = %i[admin staff viewer].include?(capability(user))

      def can_view_money?(user)     = staff?(user)
      def can_write?(user)          = staff?(user)
      def can_archive?(user)        = staff?(user)
      def can_manage_queries?(user) = staff?(user)

      # Non-builtin roles named 'CRM Contractor' that hold :view_crm_linked. Role#permissions
      # is serialized, so this is resolved in Ruby, once per request.
      def contractor_role_ids
        Memo.contractor_role_ids ||=
          Role.where(:builtin => 0).select do |r|
            r.name == RedmineCrm::CONTRACTOR_ROLE_NAME && r.has_permission?(:view_crm_linked)
          end.map(&:id)
      end

      # Active client projects on which the user holds the contractor role through a direct
      # membership, with the crm module enabled. Builtin principals never qualify.
      def contractor_project_ids(user)
        return [] unless user&.logged?
        role_ids = contractor_role_ids
        return [] if role_ids.empty?
        Memo.contractor_projects ||= {}
        Memo.contractor_projects[user.id] ||= Project.active
          .joins(:enabled_modules)
          .joins(:members => :member_roles)
          .where(:enabled_modules => {:name => 'crm'})
          .where(:members => {:user_id => user.id})
          .where(:member_roles => {:role_id => role_ids})
          .distinct.pluck(:id)
      end
    end
  end
end
