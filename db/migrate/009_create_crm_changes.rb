# frozen_string_literal: true

class CreateCrmChanges < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_changes, id: :bigint do |t|
      t.string :record_type, limit: 20, null: false
      t.bigint :record_id, null: false
      t.integer :user_id
      t.string :prop_key, limit: 60, null: false
      t.text :old_value
      t.text :value
      t.column :created_on, 'timestamptz', null: false
    end

    execute <<~SQL
      ALTER TABLE crm_changes
        ADD CONSTRAINT chk_crm_changes_record_type
        CHECK (record_type IN ('CrmAccount', 'CrmContact', 'CrmDeal', 'CrmActivity'))
    SQL
    execute <<~SQL
      CREATE INDEX idx_crm_changes_record_record_created
        ON crm_changes (record_type, record_id, created_on)
    SQL
    execute <<~SQL
      CREATE OR REPLACE FUNCTION crm_changes_append_only_guard()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'crm_changes is append-only';
      END;
      $$
    SQL
    execute <<~SQL
      CREATE TRIGGER crm_changes_append_only
      BEFORE UPDATE OR DELETE ON crm_changes
      FOR EACH ROW
      EXECUTE FUNCTION crm_changes_append_only_guard()
    SQL
  end

  def down
    execute 'DROP TRIGGER IF EXISTS crm_changes_append_only ON crm_changes'
    execute 'DROP FUNCTION IF EXISTS crm_changes_append_only_guard()'
    execute 'DROP INDEX IF EXISTS idx_crm_changes_record_record_created'
    execute 'ALTER TABLE crm_changes DROP CONSTRAINT IF EXISTS chk_crm_changes_record_type'
    drop_table :crm_changes
  end
end
