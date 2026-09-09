# frozen_string_literal: true

class CrmChange < ApplicationRecord
  self.table_name = 'crm_changes'

  RECORD_TYPES = %w[CrmAccount CrmContact CrmDeal CrmActivity].freeze

  belongs_to :user, :optional => true

  validates :record_type, :inclusion => {:in => RECORD_TYPES}
  validates :record_id, :prop_key, :presence => true
  validates :prop_key, :length => {:maximum => 60}

  before_update :prevent_mutation
  before_destroy :prevent_mutation

  private

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, 'CRM change history is append-only'
  end
end
