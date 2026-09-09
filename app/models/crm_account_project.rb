# frozen_string_literal: true

# Explicit account ↔ Redmine project bridge.  The CRM is not itself a
# Redmine project; this row is the only CRM storage that carries project_id.
class CrmAccountProject < ActiveRecord::Base
  include Crm::ActiveParentAssociation

  self.table_name = 'crm_account_projects'
  self.primary_key = nil

  belongs_to :account, :class_name => 'CrmAccount', :inverse_of => :account_projects
  belongs_to :project, :class_name => 'Project'

  crm_parent :account

  before_create :set_created_timestamp
  validates :account, :presence => true
  validates :project, :presence => true
  validates :project_id, :uniqueness => true

  after_create :write_link_change
  after_destroy :write_unlink_change

  private

  def write_link_change
    write_account_change(nil, project_label)
  end

  def write_unlink_change
    write_account_change(project_label, nil)
  end

  # History rows carry the project identifier, which stays readable after the link is gone.
  def project_label
    project ? "#{project.identifier} (#{project.id})" : project_id.to_s
  end

  def write_account_change(old_value, value)
    record = account
    return unless record && record.respond_to?(:crm_change!)

    record.crm_change!(:link_project, old_value, value, User.current)
  end

  def set_created_timestamp
    self.created_on ||= Time.current if has_attribute?(:created_on)
  end
end
