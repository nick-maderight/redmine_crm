# frozen_string_literal: true

class CreateCrmActivities < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_activities, id: :bigint do |t|
      t.string :kind, limit: 10, null: false
      t.string :channel, limit: 10
      t.string :direction, limit: 8
      t.string :subject, limit: 255
      t.text :body
      t.column :occurred_at, 'timestamptz'
      t.integer :duration_minutes, limit: 2
      t.bigint :account_id
      t.bigint :contact_id
      t.bigint :deal_id
      t.integer :author_id
      t.string :visibility, limit: 7, null: false, default: 'staff'
      t.string :external_source, limit: 32
      t.string :external_id, limit: 255
      t.integer :lock_version, null: false, default: 0
      t.column :created_on, 'timestamptz', null: false
      t.column :updated_on, 'timestamptz', null: false
      t.column :archived_on, 'timestamptz'
    end

    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT fk_crm_activities_account_id
        FOREIGN KEY (account_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT fk_crm_activities_contact_id
        FOREIGN KEY (contact_id) REFERENCES crm_contacts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT fk_crm_activities_deal_id
        FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT fk_crm_activities_author_id
        FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT chk_crm_activities_kind
        CHECK (kind IN ('note', 'call', 'meeting', 'message', 'other'))
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT chk_crm_activities_channel
        CHECK (channel IS NULL OR channel IN ('upwork', 'email', 'phone', 'sms', 'in_person', 'other'))
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT chk_crm_activities_direction
        CHECK (direction IS NULL OR direction IN ('inbound', 'outbound'))
    SQL
    execute <<~SQL
      ALTER TABLE crm_activities
        ADD CONSTRAINT chk_crm_activities_visibility
        CHECK (visibility IN ('staff', 'shared'))
    SQL

    execute <<~SQL
      CREATE INDEX idx_crm_activities_account_occurred
        ON crm_activities (account_id, occurred_at DESC)
    SQL
    execute <<~SQL
      CREATE INDEX idx_crm_activities_contact_occurred
        ON crm_activities (contact_id, occurred_at DESC)
    SQL
    execute <<~SQL
      CREATE INDEX idx_crm_activities_deal_occurred
        ON crm_activities (deal_id, occurred_at DESC)
    SQL
    execute 'CREATE INDEX idx_crm_activities_author_id ON crm_activities (author_id)'
    execute 'CREATE INDEX idx_crm_activities_archived_on ON crm_activities (archived_on)'
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_activities_external_identity
        ON crm_activities (external_source, external_id)
        WHERE external_source IS NOT NULL AND external_id IS NOT NULL
    SQL
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_activities_external_identity'
    execute 'DROP INDEX IF EXISTS idx_crm_activities_archived_on'
    execute 'DROP INDEX IF EXISTS idx_crm_activities_author_id'
    execute 'DROP INDEX IF EXISTS idx_crm_activities_deal_occurred'
    execute 'DROP INDEX IF EXISTS idx_crm_activities_contact_occurred'
    execute 'DROP INDEX IF EXISTS idx_crm_activities_account_occurred'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS chk_crm_activities_visibility'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS chk_crm_activities_direction'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS chk_crm_activities_channel'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS chk_crm_activities_kind'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS fk_crm_activities_author_id'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS fk_crm_activities_deal_id'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS fk_crm_activities_contact_id'
    execute 'ALTER TABLE crm_activities DROP CONSTRAINT IF EXISTS fk_crm_activities_account_id'
    drop_table :crm_activities
  end
end
