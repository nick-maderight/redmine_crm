# frozen_string_literal: true

class CrmAccount < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'crm_accounts'

  STATUS_VALUES = %w[lead prospect active_client past_client partner other].freeze

  belongs_to :owner, :class_name => 'User', :optional => true
  belongs_to :merged_into, :class_name => 'CrmAccount', :optional => true
  has_many :contacts, :class_name => 'CrmContact', :foreign_key => :account_id, :inverse_of => :account
  has_many :deals, :class_name => 'CrmDeal', :foreign_key => :account_id, :inverse_of => :account
  has_many :activities, :class_name => 'CrmActivity', :foreign_key => :account_id, :inverse_of => :account
  has_many :links, :class_name => 'CrmLink', :foreign_key => :account_id, :inverse_of => :account
  has_many :account_projects, :class_name => 'CrmAccountProject', :foreign_key => :account_id, :inverse_of => :account
  has_many :projects, :through => :account_projects

  acts_as_customizable
  acts_as_attachable

  include Crm::Archivable
  include Crm::Auditable
  include Crm::ActiveParentAssociation

  crm_audit_fields :name, :domain, :website, :phone, :address, :status, :owner_id,
                   :description, :external_ref, :archived_on

  safe_attributes(
    'name', 'domain', 'website', 'phone', 'address', 'status', 'owner_id',
    'description', 'custom_fields', 'custom_field_values',
    :if => lambda {|_account, user| Crm::Access.staff?(user) }
  )
  safe_attributes(
    'external_ref',
    :if => lambda {|account, user| account.new_record? && Crm::Access.staff?(user) }
  )

  validates :name, :presence => true, :length => {:maximum => 255}
  validates :status, :inclusion => {:in => STATUS_VALUES}
  validates :name, :uniqueness => {
    :case_sensitive => false,
    :conditions => -> { where(:archived_on => nil) }
  }
  validates :domain, :uniqueness => {
    :case_sensitive => false,
    :allow_nil => true,
    :conditions => -> { where(:archived_on => nil) }
  }
  validates :external_ref, :uniqueness => true, :allow_blank => true
  validate :owner_is_active_user
  validate :external_ref_immutable

  before_validation :normalize_fields

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

        joins("INNER JOIN crm_account_projects crm_account_projects_visible ON " \
              "crm_account_projects_visible.account_id = #{table_name}.id").
          where(:archived_on => nil).
          where(:crm_account_projects_visible => {:project_id => project_ids}).distinct
      else
        none
      end
    end

    def crm_search_columns
      %w[name domain description]
    end
  end

  private

  def normalize_fields
    self.name = name.to_s.strip if name
    if domain
      value = domain.to_s.strip.downcase
      value = value.sub(%r{\A[a-z][a-z0-9+.-]*://}i, '')
      value = value.split('/').first.to_s
      self.domain = value.presence
    end
    self.status = 'lead' if status.blank? && new_record?
    self.external_ref = external_ref.to_s.strip.presence if external_ref
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
