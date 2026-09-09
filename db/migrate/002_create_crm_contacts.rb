# frozen_string_literal: true

class CreateCrmContacts < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_contacts, id: :bigint do |t|
      t.bigint :account_id
      t.string :first_name, limit: 100
      t.string :last_name, limit: 100
      t.string :email, limit: 255
      t.string :phone, limit: 64
      t.string :job_title, limit: 120
      t.string :city, limit: 120
      t.string :linkedin_url, limit: 255
      t.string :x_url, limit: 255
      t.integer :owner_id
      t.string :external_ref, limit: 120
      t.integer :lock_version, null: false, default: 0
      t.column :created_on, 'timestamptz', null: false
      t.column :updated_on, 'timestamptz', null: false
      t.column :archived_on, 'timestamptz'
      t.bigint :merged_into_id
    end

    execute <<~SQL
      ALTER TABLE crm_contacts
        ADD CONSTRAINT chk_crm_contacts_name_present
        CHECK (
          btrim(COALESCE(first_name, '')) <> ''
          OR btrim(COALESCE(last_name, '')) <> ''
        )
    SQL
    execute <<~SQL
      ALTER TABLE crm_contacts
        ADD CONSTRAINT chk_crm_contacts_email_not_blank
        CHECK (email IS NULL OR email <> '')
    SQL
    execute <<~SQL
      ALTER TABLE crm_contacts
        ADD CONSTRAINT fk_crm_contacts_account_id
        FOREIGN KEY (account_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_contacts
        ADD CONSTRAINT fk_crm_contacts_owner_id
        FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL
    SQL
    execute <<~SQL
      ALTER TABLE crm_contacts
        ADD CONSTRAINT fk_crm_contacts_merged_into_id
        FOREIGN KEY (merged_into_id) REFERENCES crm_contacts(id) ON DELETE RESTRICT
    SQL

    execute 'CREATE INDEX idx_crm_contacts_account_id ON crm_contacts (account_id)'
    execute 'CREATE INDEX idx_crm_contacts_merged_into_id ON crm_contacts (merged_into_id)'
    execute 'CREATE INDEX idx_crm_contacts_lower_last_name ON crm_contacts (lower(last_name))'
    execute 'CREATE INDEX idx_crm_contacts_lower_first_name ON crm_contacts (lower(first_name))'
    execute 'CREATE INDEX idx_crm_contacts_owner_id ON crm_contacts (owner_id)'
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_contacts_active_lower_email
        ON crm_contacts (lower(email))
        WHERE email IS NOT NULL AND archived_on IS NULL
    SQL
    execute 'CREATE UNIQUE INDEX idx_crm_contacts_external_ref ON crm_contacts (external_ref)'
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_external_ref'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_active_lower_email'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_owner_id'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_lower_first_name'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_lower_last_name'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_merged_into_id'
    execute 'DROP INDEX IF EXISTS idx_crm_contacts_account_id'
    execute 'ALTER TABLE crm_contacts DROP CONSTRAINT IF EXISTS fk_crm_contacts_merged_into_id'
    execute 'ALTER TABLE crm_contacts DROP CONSTRAINT IF EXISTS fk_crm_contacts_owner_id'
    execute 'ALTER TABLE crm_contacts DROP CONSTRAINT IF EXISTS fk_crm_contacts_account_id'
    execute 'ALTER TABLE crm_contacts DROP CONSTRAINT IF EXISTS chk_crm_contacts_email_not_blank'
    execute 'ALTER TABLE crm_contacts DROP CONSTRAINT IF EXISTS chk_crm_contacts_name_present'
    drop_table :crm_contacts
  end
end
