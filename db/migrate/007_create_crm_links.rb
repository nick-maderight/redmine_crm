# frozen_string_literal: true

class CreateCrmLinks < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_links, id: :bigint do |t|
      t.bigint :account_id
      t.bigint :contact_id
      t.bigint :deal_id
      t.integer :issue_id, null: false
      t.column :created_on, 'timestamptz', null: false
    end

    execute <<~SQL
      ALTER TABLE crm_links
        ADD CONSTRAINT fk_crm_links_account_id
        FOREIGN KEY (account_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_links
        ADD CONSTRAINT fk_crm_links_contact_id
        FOREIGN KEY (contact_id) REFERENCES crm_contacts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_links
        ADD CONSTRAINT fk_crm_links_deal_id
        FOREIGN KEY (deal_id) REFERENCES crm_deals(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_links
        ADD CONSTRAINT fk_crm_links_issue_id
        FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
    SQL
    execute <<~SQL
      ALTER TABLE crm_links
        ADD CONSTRAINT chk_crm_links_one_target
        CHECK (num_nonnulls(account_id, contact_id, deal_id) = 1)
    SQL

    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_links_account_issue_unique
        ON crm_links (account_id, issue_id)
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_links_contact_issue_unique
        ON crm_links (contact_id, issue_id)
    SQL
    execute <<~SQL
      CREATE UNIQUE INDEX idx_crm_links_deal_issue_unique
        ON crm_links (deal_id, issue_id)
    SQL
    execute 'CREATE INDEX idx_crm_links_issue_id ON crm_links (issue_id)'
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_links_issue_id'
    execute 'DROP INDEX IF EXISTS idx_crm_links_deal_issue_unique'
    execute 'DROP INDEX IF EXISTS idx_crm_links_contact_issue_unique'
    execute 'DROP INDEX IF EXISTS idx_crm_links_account_issue_unique'
    execute 'ALTER TABLE crm_links DROP CONSTRAINT IF EXISTS chk_crm_links_one_target'
    execute 'ALTER TABLE crm_links DROP CONSTRAINT IF EXISTS fk_crm_links_issue_id'
    execute 'ALTER TABLE crm_links DROP CONSTRAINT IF EXISTS fk_crm_links_deal_id'
    execute 'ALTER TABLE crm_links DROP CONSTRAINT IF EXISTS fk_crm_links_contact_id'
    execute 'ALTER TABLE crm_links DROP CONSTRAINT IF EXISTS fk_crm_links_account_id'
    drop_table :crm_links
  end
end
