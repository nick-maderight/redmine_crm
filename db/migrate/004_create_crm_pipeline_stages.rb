# frozen_string_literal: true

class CreateCrmPipelineStages < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_pipeline_stages, id: :bigint do |t|
      t.bigint :pipeline_id, null: false
      t.string :name, limit: 60, null: false
      t.integer :position, null: false
      t.integer :probability, limit: 2, null: false
      t.string :kind, limit: 6, null: false
      t.string :color, limit: 7
      t.string :followup_text, limit: 255
      t.integer :followup_due_days, limit: 2
      t.column :created_on, 'timestamptz', null: false
    end

    execute <<~SQL
      ALTER TABLE crm_pipeline_stages
        ADD CONSTRAINT fk_crm_pipeline_stages_pipeline_id
        FOREIGN KEY (pipeline_id) REFERENCES crm_pipelines(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_pipeline_stages
        ADD CONSTRAINT chk_crm_pipeline_stages_probability
        CHECK (probability BETWEEN 0 AND 100)
    SQL
    execute <<~SQL
      ALTER TABLE crm_pipeline_stages
        ADD CONSTRAINT chk_crm_pipeline_stages_kind
        CHECK (kind IN ('open', 'won', 'lost'))
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_pipeline_stages_pipeline_position
        ON crm_pipeline_stages (pipeline_id, position)
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_pipeline_stages_pipeline_name
        ON crm_pipeline_stages (pipeline_id, name)
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_pipeline_stages_pipeline_id_id
        ON crm_pipeline_stages (pipeline_id, id)
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_pipeline_stages_pipeline_id_id'
    execute 'DROP INDEX IF EXISTS idx_crm_pipeline_stages_pipeline_name'
    execute 'DROP INDEX IF EXISTS idx_crm_pipeline_stages_pipeline_position'
    execute 'ALTER TABLE crm_pipeline_stages DROP CONSTRAINT IF EXISTS chk_crm_pipeline_stages_kind'
    execute 'ALTER TABLE crm_pipeline_stages DROP CONSTRAINT IF EXISTS chk_crm_pipeline_stages_probability'
    execute 'ALTER TABLE crm_pipeline_stages DROP CONSTRAINT IF EXISTS fk_crm_pipeline_stages_pipeline_id'
    drop_table :crm_pipeline_stages
  end
end
