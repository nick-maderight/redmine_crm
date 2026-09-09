# frozen_string_literal: true

class CreateCrmAccounts < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_accounts, id: :bigint do |t|
      t.string :name, limit: 255, null: false
      t.string :domain, limit: 255
      t.string :website, limit: 255
      t.string :phone, limit: 64
      t.text :address
      t.string :status, limit: 20, null: false, default: 'lead'
      t.integer :owner_id
      t.text :description
      t.string :external_ref, limit: 120
      t.integer :lock_version, null: false, default: 0
      t.column :created_on, 'timestamptz', null: false
      t.column :updated_on, 'timestamptz', null: false
      t.column :archived_on, 'timestamptz'
      t.bigint :merged_into_id
    end

    execute <<~SQL
      ALTER TABLE crm_accounts
        ADD CONSTRAINT chk_crm_accounts_status
        CHECK (status IN ('lead', 'prospect', 'active_client', 'past_client', 'partner', 'other'))
    SQL
    execute <<~SQL
      ALTER TABLE crm_accounts
        ADD CONSTRAINT fk_crm_accounts_owner_id
        FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL
    SQL
    execute <<~SQL
      ALTER TABLE crm_accounts
        ADD CONSTRAINT fk_crm_accounts_merged_into_id
        FOREIGN KEY (merged_into_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_accounts_active_lower_name
        ON crm_accounts (lower(name))
        WHERE archived_on IS NULL
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_accounts_active_lower_domain
        ON crm_accounts (lower(domain))
        WHERE domain IS NOT NULL AND archived_on IS NULL
    SQL
    execute 'CREATE INDEX idx_crm_accounts_status ON crm_accounts (status)'
    execute 'CREATE INDEX idx_crm_accounts_owner_id ON crm_accounts (owner_id)'
    execute 'CREATE INDEX idx_crm_accounts_merged_into_id ON crm_accounts (merged_into_id)'
    execute 'CREATE UNIQUE INDEX idx_crm_accounts_external_ref ON crm_accounts (external_ref)'
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_external_ref'
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_merged_into_id'
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_owner_id'
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_status'
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_active_lower_domain'
    execute 'DROP INDEX IF EXISTS idx_crm_accounts_active_lower_name'
    execute 'ALTER TABLE crm_accounts DROP CONSTRAINT IF EXISTS fk_crm_accounts_merged_into_id'
    execute 'ALTER TABLE crm_accounts DROP CONSTRAINT IF EXISTS fk_crm_accounts_owner_id'
    execute 'ALTER TABLE crm_accounts DROP CONSTRAINT IF EXISTS chk_crm_accounts_status'
    drop_table :crm_accounts
  end
end
