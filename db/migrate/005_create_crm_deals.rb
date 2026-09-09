# frozen_string_literal: true

class CreateCrmDeals < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_deals, id: :bigint do |t|
      t.string :name, limit: 255, null: false
      t.text :description
      t.bigint :account_id
      t.bigint :contact_id
      t.bigint :pipeline_id, null: false
      t.bigint :stage_id, null: false
      t.integer :owner_id
      t.bigint :amount_cents
      t.column :currency, 'char(3)', null: false, default: 'USD'
      t.integer :probability, limit: 2
      t.date :expected_close_on
      t.date :closed_on
      t.string :next_action, limit: 255
      t.date :next_action_on
      t.string :external_ref, limit: 120
      t.integer :lock_version, null: false, default: 0
      t.column :created_on, 'timestamptz', null: false
      t.column :updated_on, 'timestamptz', null: false
      t.column :archived_on, 'timestamptz'
    end

    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT fk_crm_deals_account_id
        FOREIGN KEY (account_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT fk_crm_deals_contact_id
        FOREIGN KEY (contact_id) REFERENCES crm_contacts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT fk_crm_deals_pipeline_id
        FOREIGN KEY (pipeline_id) REFERENCES crm_pipelines(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT fk_crm_deals_owner_id
        FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL
    SQL
    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT fk_crm_deals_pipeline_stage
        FOREIGN KEY (pipeline_id, stage_id)
        REFERENCES crm_pipeline_stages(pipeline_id, id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_deals
        ADD CONSTRAINT chk_crm_deals_probability
        CHECK (probability IS NULL OR probability BETWEEN 0 AND 100)
    SQL

    execute 'CREATE INDEX idx_crm_deals_account_id ON crm_deals (account_id)'
    execute 'CREATE INDEX idx_crm_deals_contact_id ON crm_deals (contact_id)'
    execute 'CREATE INDEX idx_crm_deals_pipeline_stage ON crm_deals (pipeline_id, stage_id)'
    execute 'CREATE INDEX idx_crm_deals_owner_id ON crm_deals (owner_id)'
    execute 'CREATE INDEX idx_crm_deals_expected_close_on ON crm_deals (expected_close_on)'
    execute 'CREATE INDEX idx_crm_deals_closed_on ON crm_deals (closed_on)'
    execute <<~SQL
      CREATE INDEX idx_crm_deals_next_action_on_active
        ON crm_deals (next_action_on)
        WHERE archived_on IS NULL AND next_action_on IS NOT NULL
    SQL
    execute 'CREATE UNIQUE INDEX idx_crm_deals_external_ref ON crm_deals (external_ref)'
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_deals_external_ref'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_next_action_on_active'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_closed_on'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_expected_close_on'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_owner_id'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_pipeline_stage'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_contact_id'
    execute 'DROP INDEX IF EXISTS idx_crm_deals_account_id'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS chk_crm_deals_probability'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS fk_crm_deals_pipeline_stage'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS fk_crm_deals_owner_id'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS fk_crm_deals_pipeline_id'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS fk_crm_deals_contact_id'
    execute 'ALTER TABLE crm_deals DROP CONSTRAINT IF EXISTS fk_crm_deals_account_id'
    drop_table :crm_deals
  end
end
