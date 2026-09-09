# frozen_string_literal: true

class CreateCrmPipelines < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_pipelines, id: :bigint do |t|
      t.string :name, limit: 60, null: false
      t.integer :position, null: false
      t.boolean :is_default, null: false, default: false
      t.column :created_on, 'timestamptz', null: false
    end

    execute 'CREATE UNIQUE INDEX idx_crm_pipelines_name_unique ON crm_pipelines (name)'
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_pipelines_default_unique
        ON crm_pipelines (is_default)
        WHERE is_default
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_pipelines_default_unique'
    execute 'DROP INDEX IF EXISTS idx_crm_pipelines_name_unique'
    drop_table :crm_pipelines
  end
end
