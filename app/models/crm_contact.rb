# frozen_string_literal: true

class CrmContact < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'crm_contacts'

  belongs_to :account, :class_name => 'CrmAccount', :optional => true, :inverse_of => :contacts
  belongs_to :owner, :class_name => 'User', :optional => true
  belongs_to :merged_into, :class_name => 'CrmContact', :optional => true
  has_many :deals, :class_name => 'CrmDeal', :foreign_key => :contact_id, :inverse_of => :contact
  has_many :activities, :class_name => 'CrmActivity', :foreign_key => :contact_id, :inverse_of => :contact
  has_many :links, :class_name => 'CrmLink', :foreign_key => :contact_id, :inverse_of => :contact

  acts_as_customizable
  acts_as_attachable

  include Crm::Archivable
  include Crm::Auditable
  include Crm::ActiveParentAssociation

  crm_parent :account
  crm_audit_fields :account_id, :first_name, :last_name, :email, :phone, :job_title,
                   :city, :linkedin_url, :x_url, :owner_id, :external_ref, :archived_on

  safe_attributes(
    'account_id', 'first_name', 'last_name', 'email', 'phone', 'job_title', 'city',
    'linkedin_url', 'x_url', 'owner_id', 'custom_fields', 'custom_field_values',
    :if => lambda {|_contact, user| Crm::Access.staff?(user) }
  )
  safe_attributes(
    'external_ref',
    :if => lambda {|contact, user| contact.new_record? && (Crm::Access.staff?(user) || Crm::Access.feed?(user)) }
  )
  safe_attributes(
    'account_id', 'first_name', 'last_name', 'email', 'phone', 'job_title',
    :if => lambda {|contact, user| contact.new_record? && Crm::Access.feed?(user) }
  )

  validates :first_name, :length => {:maximum => 100}
  validates :last_name, :length => {:maximum => 100}
  validates :email, :length => {:maximum => 255}, :allow_nil => true
  validates :email, :uniqueness => {
    :case_sensitive => false,
    :allow_nil => true,
    :conditions => -> { where(:archived_on => nil) }
  }
  validates :external_ref, :uniqueness => true, :allow_blank => true
  validate :one_name_present
  validate :owner_is_active_user
  validate :external_ref_immutable

  before_validation :normalize_email

  class << self
    def visible(user=User.current, include_archived: false)
      case Crm::Access.capability(user)
      when :admin, :staff, :viewer
        scope = all
        scope = scope.where(:archived_on => nil) unless include_archived
        scope
      when :contractor
        project_ids = Crm::Access.contractor_project_ids(user)
        return none if project_ids.empty?

        where(:archived_on => nil, :account_id => CrmAccount.visible(user).select(:id))
      else
        none
      end
    end

    def crm_search_columns
      %w[first_name last_name email job_title]
    end
  end

  def name
    [first_name, last_name].compact.map(&:to_s).map(&:strip).reject(&:blank?).join(' ')
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence if email
    self.external_ref = external_ref.to_s.strip.presence if external_ref
  end

  def one_name_present
    return if first_name.to_s.strip.present? || last_name.to_s.strip.present?

    errors.add(:base, :blank)
  end

  def owner_is_active_user
    return if owner_id.blank?

    valid_owner = User.where(:id => owner_id, :type => 'User', :status => User::STATUS_ACTIVE).exists?
    errors.add(:owner_id, :invalid) unless valid_owner
  end

  def external_ref_immutable
    return unless persisted? && will_save_change_to_external_ref?

    errors.add(:external_ref, :invalid)
  end
end
