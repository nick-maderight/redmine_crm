# frozen_string_literal: true

# CRM timeline activities are globally scoped records.  Their visibility is
# deliberately kept here, rather than delegated to Redmine's project-scoped
# activity or attachment APIs.
class CrmActivity < ActiveRecord::Base
  include Redmine::SafeAttributes
  include Redmine::Acts::Attachable
  include Crm::Archivable
  include Crm::Auditable
  include Crm::ActiveParentAssociation

  self.table_name = 'crm_activities'
  KINDS = %w[note call meeting message other].freeze
  CHANNELS = %w[upwork email phone sms in_person other].freeze
  DIRECTIONS = %w[inbound outbound].freeze
  VISIBILITIES = %w[staff shared].freeze
  AUDIT_FIELDS = %i[
    body subject kind channel direction occurred_at duration_minutes
    account_id contact_id deal_id visibility
  ].freeze

  belongs_to :account, :class_name => 'CrmAccount', :optional => true, :inverse_of => :activities
  belongs_to :contact, :class_name => 'CrmContact', :optional => true, :inverse_of => :activities
  belongs_to :deal, :class_name => 'CrmDeal', :optional => true, :inverse_of => :activities
  belongs_to :author, :class_name => 'User', :foreign_key => :author_id, :optional => true

  acts_as_attachable
  crm_parent :account, :contact, :deal
  crm_audit_fields(*AUDIT_FIELDS)

  # The timeline's ordinary scope is active rows.  The explicit visibility
  # methods below use unscoped so that staff can request archived rows without
  # accidentally widening contractor access.
  default_scope { where(:archived_on => nil) }
  scope :active, -> { where(:archived_on => nil) }
  scope :archived, -> { unscope(:where).where.not(:archived_on => nil) }

  before_validation :set_activity_defaults
  before_validation :backfill_account_from_subject
  before_validation :assign_author_from_current_user
  before_create :set_created_timestamp
  before_save :set_updated_timestamp

  validates :kind, :presence => true, :inclusion => {:in => KINDS}
  validates :channel, :inclusion => {:in => CHANNELS}, :allow_nil => true
  validates :direction, :inclusion => {:in => DIRECTIONS}, :allow_nil => true
  validates :visibility, :presence => true, :inclusion => {:in => VISIBILITIES}
  validates :occurred_at, :presence => true
  validates :duration_minutes, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0},
            :allow_nil => true
  validates :external_source, :length => {:maximum => 32}, :allow_blank => true
  validates :external_id, :length => {:maximum => 255}, :allow_blank => true
  validate :external_identity_is_unique
  validate :external_identity_is_immutable
  validate :shared_activity_has_one_account

  safe_attributes(
    'kind', 'channel', 'direction', 'subject', 'body', 'occurred_at',
    'duration_minutes', 'account_id', 'contact_id', 'deal_id', 'visibility',
    'lock_version',
    :if => lambda {|activity, user| Crm::Access.staff?(user)}
  )
  safe_attributes(
    'external_source', 'external_id',
    :if => lambda {|activity, user| activity.new_record? && Crm::Access.staff?(user)}
  )
  safe_attributes(
    'kind', 'channel', 'direction', 'subject', 'body', 'occurred_at',
    'duration_minutes', 'account_id', 'contact_id', 'deal_id',
    'external_source', 'external_id',
    :if => lambda {|activity, user| activity.new_record? && Crm::Access.feed?(user)}
  )

  class << self
    # Staff and viewers can see all activities (including staff-only rows).
    # Contractors receive only shared activities attached to one of their
    # visible accounts, through any of the three supported associations.
    def visible(user, include_archived: false)
      # `all` keeps an association's own conditions (record.activities.visible(user));
      # `unscoped` would silently widen the timeline to every activity.
      scope = include_archived ? all.unscope(:where => :archived_on) : all.where(:archived_on => nil)
      capability = Crm::Access.capability(user)

      case capability
      when :admin, :staff, :viewer
        scope
      when :contractor
        scope = all.where(:archived_on => nil)
        account_ids = CrmAccount.visible(user).pluck(:id)
        return scope.none if account_ids.empty?

        scope.
          left_joins(:contact, :deal).
          where(:visibility => 'shared').
          where(
            "#{table_name}.account_id IN (:ids) OR " \
            "crm_contacts.account_id IN (:ids) OR " \
            "crm_deals.account_id IN (:ids)",
            :ids => account_ids
          )
      else
        scope.none
      end
    end

    def for_api(user, include_archived: false)
      visible(user, include_archived: include_archived)
    end

    def search_result_ranks_and_ids(tokens, user = User.current, _projects = nil, options = {})
      return [] if options[:attachments] == 'only'

      words = Array(tokens).flatten.compact.map(&:to_s).reject(&:blank?)
      return [] if words.empty?

      columns = options[:titles_only] ? %w[subject] : %w[subject body]
      predicates = words.map do |_word|
        columns.map {|column| "#{table_name}.#{column} ILIKE ?"}.join(' OR ').yield_self {|sql| "(#{sql})"}
      end
      pattern_values = words.flat_map {|word| columns.map {|_column| "%#{sanitize_sql_like(word)}%"}}
      relation = visible(user).where(predicates.join(options[:all_words] ? ' AND ' : ' OR '), *pattern_values)
      relation.
        reorder(:occurred_at => :desc, :id => :desc).
        limit(options[:limit]).
        pluck(:occurred_at, :id).
        map {|timestamp, id| [timestamp ? timestamp.to_i : 0, id]}
    end

    def search_results_from_ids(ids)
      where(:id => Array(ids).compact).preload(:account, :contact, :deal, :author).to_a
    end
  end

  def visible?(user = User.current, include_archived: false)
    self.class.visible(user, include_archived: include_archived).where(:id => id).exists?
  end

  # CRM attachments are not project attachments.  Files are available only
  # to staff/viewers and never to contractors or the feed identity.
  def attachments_visible?(user = User.current)
    visible?(user, include_archived: true) && Crm::Access.reads_all?(user)
  end

  def attachments_editable?(user = User.current)
    visible?(user, include_archived: true) && Crm::Access.can_write?(user)
  end

  def attachments_deletable?(user = User.current)
    attachments_editable?(user)
  end

  # Activities may be associated with an archived, unmerged parent for staff
  # and feed writes.  The association concern calls this hook when deciding
  # whether an archived parent is acceptable.
  def crm_archived_parent_allowed?
    true
  end

  private

  def set_activity_defaults
    self.visibility = 'staff' if visibility.blank?
  end

  def backfill_account_from_subject
    return if account_id.present?

    self.account_id = deal&.account_id if deal_id.present?
    self.account_id ||= contact&.account_id if account_id.blank? && contact_id.present?
  end

  def assign_author_from_current_user
    return unless new_record? && author_id.blank?
    return unless defined?(User) && User.respond_to?(:current)

    current = User.current
    self.author_id = current.id if current.respond_to?(:logged?) && current.logged?
  end

  def external_identity_is_immutable
    return unless persisted?
    return unless will_save_change_to_external_source? || will_save_change_to_external_id?

    errors.add(:base, 'external_source and external_id are immutable after creation')
  end

  def external_identity_is_unique
    return if external_source.blank? || external_id.blank?

    relation = self.class.unscoped.where(
      :external_source => external_source,
      :external_id => external_id
    )
    relation = relation.where.not(:id => id) if persisted?
    errors.add(:base, 'external_source and external_id must be unique') if relation.exists?
  end

  def shared_activity_has_one_account
    return unless visibility == 'shared'

    account_ids = []
    account_ids << account_id if account_id.present?
    account_ids << contact.account_id if contact&.account_id.present?
    account_ids << deal.account_id if deal&.account_id.present?
    account_ids.uniq!
    errors.add(:base, 'shared activities must resolve to one account') if account_ids.length > 1
  end

  def set_created_timestamp
    now = Time.current
    self.created_on ||= now if has_attribute?(:created_on)
    self.updated_on ||= self.created_on || now if has_attribute?(:updated_on)
  end

  def set_updated_timestamp
    self.updated_on = Time.current if has_attribute?(:updated_on)
  end
end
