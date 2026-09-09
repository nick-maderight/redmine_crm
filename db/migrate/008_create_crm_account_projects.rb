# frozen_string_literal: true

class CreateCrmAccountProjects < ActiveRecord::Migration[8.1]
  def up
    create_table :crm_account_projects, id: false do |t|
      t.bigint :account_id, null: false
      t.integer :project_id, null: false
      t.column :created_on, 'timestamptz', null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end

    execute <<~SQL
      ALTER TABLE crm_account_projects
        ADD CONSTRAINT pk_crm_account_projects
        PRIMARY KEY (account_id, project_id)
    SQL
    execute <<~SQL
      ALTER TABLE crm_account_projects
        ADD CONSTRAINT fk_crm_account_projects_account_id
        FOREIGN KEY (account_id) REFERENCES crm_accounts(id) ON DELETE RESTRICT
    SQL
    execute <<~SQL
      ALTER TABLE crm_account_projects
        ADD CONSTRAINT fk_crm_account_projects_project_id
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
    SQL
    execute 'CREATE UNIQUE INDEX idx_crm_account_projects_project_id_unique ON crm_account_projects (project_id)'
  end

  def down
    execute 'DROP INDEX IF EXISTS idx_crm_account_projects_project_id_unique'
    execute 'ALTER TABLE crm_account_projects DROP CONSTRAINT IF EXISTS fk_crm_account_projects_project_id'
    execute 'ALTER TABLE crm_account_projects DROP CONSTRAINT IF EXISTS fk_crm_account_projects_account_id'
    execute 'ALTER TABLE crm_account_projects DROP CONSTRAINT IF EXISTS pk_crm_account_projects'
    drop_table :crm_account_projects
  end
end
