# frozen_string_literal: true

class CrmPipelineStage < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'crm_pipeline_stages'

  KINDS = %w[open won lost].freeze

  belongs_to :pipeline, :class_name => 'CrmPipeline', :inverse_of => :stages
  has_many :deals, :class_name => 'CrmDeal', :foreign_key => :stage_id, :inverse_of => :stage

  safe_attributes(
    'pipeline_id', 'name', 'position', 'probability', 'kind', 'color',
    'followup_text', 'followup_due_days',
    :if => lambda {|_stage, user| Crm::Access.admin?(user) }
  )

  validates :name, :presence => true, :length => {:maximum => 60}
  validates :position, :numericality => {:only_integer => true}
  validates :probability, :numericality => {
    :only_integer => true, :greater_than_or_equal_to => 0, :less_than_or_equal_to => 100
  }
  validates :kind, :inclusion => {:in => KINDS}
  validates :color, :format => {:with => /\A\#[0-9a-f]{6}\z/i}, :allow_blank => true
  validates :followup_due_days, :numericality => {:only_integer => true, :greater_than_or_equal_to => 0}, :allow_nil => true
  validates :name, :uniqueness => {:scope => :pipeline_id}
  validates :position, :uniqueness => {:scope => :pipeline_id}
  validate :pipeline_presence
  validate :must_leave_an_open_stage
  before_destroy :prevent_last_open_destroy

  class << self
    def first_open(pipeline_or_id=nil)
      pipeline_id = pipeline_or_id ? (pipeline_or_id.respond_to?(:id) ? pipeline_or_id.id : pipeline_or_id) : CrmPipeline.default&.id
      return nil if pipeline_id.blank?

      where(:pipeline_id => pipeline_id, :kind => 'open').order(:position, :id).first
    end
  end

  def first_open
    self.class.first_open(pipeline_id)
  end

  def open?
    kind == 'open'
  end

  def won?
    kind == 'won'
  end

  def lost?
    kind == 'lost'
  end

  private

  def pipeline_presence
    errors.add(:pipeline_id, :blank) if pipeline_id.blank?
  end

  def must_leave_an_open_stage
    return unless persisted? && will_save_change_to_kind? && kind != 'open'
    return if self.class.where(:pipeline_id => pipeline_id, :kind => 'open').where.not(:id => id).exists?

    errors.add(:kind, :invalid)
  end

  def prevent_last_open_destroy
    if open? && !self.class.where(:pipeline_id => pipeline_id, :kind => 'open').where.not(:id => id).exists?
      errors.add(:base, :invalid)
      throw(:abort)
    end
  end
end
