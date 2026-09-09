# frozen_string_literal: true

class CrmPipeline < ApplicationRecord
  include Redmine::SafeAttributes

  self.table_name = 'crm_pipelines'

  has_many :stages, -> { order(:position, :id) }, :class_name => 'CrmPipelineStage', :foreign_key => :pipeline_id, :inverse_of => :pipeline, :dependent => :restrict_with_error
  has_many :deals, :class_name => 'CrmDeal', :foreign_key => :pipeline_id, :inverse_of => :pipeline

  safe_attributes(
    'name', 'position', 'is_default',
    :if => lambda {|_pipeline, user| Crm::Access.admin?(user) }
  )

  validates :name, :presence => true, :length => {:maximum => 60}, :uniqueness => true
  validates :position, :numericality => {:only_integer => true}, :allow_nil => true

  validate :cannot_unset_only_default
  before_save :make_default_exclusive
  before_destroy :prevent_destroy_when_referenced

  def self.default
    where(:is_default => true).order(:position, :id).first
  end

  def default?
    is_default?
  end

  def first_open
    stages.where(:kind => 'open').order(:position, :id).first
  end

  private

  def cannot_unset_only_default
    return unless persisted? && will_save_change_to_is_default? && !is_default?
    return if self.class.where.not(:id => id).where(:is_default => true).exists?

    errors.add(:is_default, :invalid)
  end

  def make_default_exclusive
    return unless is_default?

    self.class.where.not(:id => id).where(:is_default => true).update_all(:is_default => false)
  end

  def prevent_destroy_when_referenced
    if is_default? && !self.class.where.not(:id => id).where(:is_default => true).exists?
      errors.add(:base, :invalid)
      throw(:abort)
    end
    if stages.exists? || deals.exists?
      errors.add(:base, :invalid)
      throw(:abort)
    end
  end
end
