# frozen_string_literal: true

# A CRM link is a reference between one CRM record and one Redmine issue.  It
# is intentionally not polymorphic: the database has three nullable foreign
# keys and a check constraint enforcing exactly one target.
class CrmLink < ActiveRecord::Base
  include Crm::ActiveParentAssociation

  self.table_name = 'crm_links'

  belongs_to :account, :class_name => 'CrmAccount', :optional => true, :inverse_of => :links
  belongs_to :contact, :class_name => 'CrmContact', :optional => true, :inverse_of => :links
  belongs_to :deal, :class_name => 'CrmDeal', :optional => true, :inverse_of => :links
  belongs_to :issue, :class_name => 'Issue'

  crm_parent :account, :contact, :deal

  before_create :set_created_timestamp
  validate :exactly_one_crm_target
  validates :issue, :presence => true

  after_create :write_link_change
  after_destroy :write_unlink_change

  def target
    account || contact || deal
  end

  def target_type
    return 'CrmAccount' if account_id.present?
    return 'CrmContact' if contact_id.present?
    return 'CrmDeal' if deal_id.present?

    nil
  end

  private

  def exactly_one_crm_target
    count = [account_id, contact_id, deal_id].compact.length
    errors.add(:base, 'exactly one CRM target is required') unless count == 1
  end

  def write_link_change
    write_target_change(nil, issue_id)
  end

  def write_unlink_change
    write_target_change(issue_id, nil)
  end

  def write_target_change(old_value, value)
    record = target
    return unless record && record.respond_to?(:crm_change!)

    record.crm_change!(:link_issue, old_value, value, User.current)
  end

  def set_created_timestamp
    self.created_on ||= Time.current if has_attribute?(:created_on)
  end
end
