# frozen_string_literal: true

class CrmDeal < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'crm_deals'
  attr_accessor :crm_stage_entry_date

  belongs_to :account, :class_name => 'CrmAccount', :optional => true, :inverse_of => :deals
  belongs_to :contact, :class_name => 'CrmContact', :optional => true, :inverse_of => :deals
  belongs_to :pipeline, :class_name => 'CrmPipeline', :inverse_of => :deals
  belongs_to :stage, :class_name => 'CrmPipelineStage', :foreign_key => :stage_id, :inverse_of => :deals
  belongs_to :owner, :class_name => 'User', :optional => true
  has_many :activities, :class_name => 'CrmActivity', :foreign_key => :deal_id, :inverse_of => :deal
  has_many :links, :class_name => 'CrmLink', :foreign_key => :deal_id, :inverse_of => :deal

  acts_as_customizable
  acts_as_attachable

  include Crm::Archivable
  include Crm::Auditable
  include Crm::ActiveParentAssociation

  crm_parent :account, :contact
  crm_audit_fields :name, :description, :account_id, :contact_id, :pipeline_id, :stage_id, :owner_id,
                   :amount_cents, :currency, :probability, :expected_close_on,
                   :closed_on, :next_action, :next_action_on, :external_ref, :archived_on

  safe_attributes(
    'name', 'description', 'account_id', 'contact_id', 'pipeline_id', 'stage_id', 'owner_id',
    'amount_cents', 'currency', 'probability', 'expected_close_on', 'next_action',
    'next_action_on', 'custom_fields', 'custom_field_values',
    :if => lambda {|_deal, user| Crm::Access.staff?(user) }
  )
  safe_attributes(
    'external_ref',
    :if => lambda {|deal, user| deal.new_record? && (Crm::Access.staff?(user) || Crm::Access.feed?(user)) }
  )
  safe_attributes(
    'name', 'contact_id', 'account_id',
    :if => lambda {|deal, user| deal.new_record? && Crm::Access.feed?(user) }
  )

  validates :name, :presence => true, :length => {:maximum => 255}
  validates :currency, :format => {:with => /\A[A-Z]{3}\z/}
  validates :amount_cents, :numericality => {:only_integer => true}, :allow_nil => true
  validates :probability, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0, :less_than_or_equal_to => 100}, :allow_nil => true
  validates :external_ref, :uniqueness => true, :allow_blank => true
  validates :pipeline, :presence => true
  validates :stage, :presence => true
  validate :stage_belongs_to_pipeline
  validate :owner_is_active_user
  validate :external_ref_immutable

  before_validation :assign_defaults
  before_validation :normalize_currency
  before_save :apply_stage_state, :if => -> { !new_record? && will_save_change_to_stage_id? }

  class << self
    def visible(user=User.current, include_archived: false)
      case Crm::Access.capability(user)
      when :admin, :staff, :viewer
        scope = all
        scope = scope.where(:archived_on => nil) unless include_archived
        scope
      else
        none
      end
    end

    def crm_search_columns
      %w[name next_action external_ref]
    end
  end

  def stage_kind
    stage && stage.kind
  end

  def open?
    stage_kind == 'open'
  end

  def won?
    stage_kind == 'won'
  end

  def lost?
    stage_kind == 'lost'
  end

  def closed?
    won? || lost?
  end

  def weighted_cents
    return nil if amount_cents.nil?

    amount_cents * (probability || stage&.probability || 0) / 100
  end

  private

  def assign_defaults
    if pipeline_id.blank?
      self.pipeline = CrmPipeline.default
      self.pipeline_id = pipeline&.id
    end
    if stage_id.blank? && pipeline
      self.stage = pipeline.first_open
      self.stage_id = stage&.id
    end
    if account_id.blank? && contact
      self.account_id = contact.account_id if contact.account_id.present?
    end
    errors.add(:pipeline_id, :blank) if pipeline.blank?
    errors.add(:stage_id, :blank) if stage.blank?
  end

  def normalize_currency
    self.currency = currency.to_s.strip.upcase
    self.currency = 'USD' if currency.blank?
    self.external_ref = external_ref.to_s.strip.presence if external_ref
  end

  def apply_stage_state
    return unless stage
    return unless will_save_change_to_stage_id?

    entry_date = crm_stage_entry_date || begin
      current_user = User.current
      current_user.respond_to?(:today) ? current_user.today : Date.current
    end

    if stage.won? || stage.lost?
      self.closed_on = entry_date
    else
      self.closed_on = nil
    end

    if stage.followup_text.present?
      self.next_action = stage.followup_text
      self.next_action_on = stage.followup_due_days.present? ? entry_date + stage.followup_due_days.to_i : nil
    else
      self.next_action = nil
      self.next_action_on = nil
    end
  end

  def stage_belongs_to_pipeline
    return if pipeline_id.blank? || stage_id.blank? || stage.blank?
    return if stage.pipeline_id.to_i == pipeline_id.to_i

    errors.add(:stage_id, :invalid)
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
