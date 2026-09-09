# CRM schema names

The plugin migrations use explicit names for every non-implicit constraint and index. The
primary-key constraints are PostgreSQL's implicit names: `crm_accounts_pkey`,
`crm_contacts_pkey`, `crm_pipelines_pkey`, `crm_pipeline_stages_pkey`, `crm_deals_pkey`,
`crm_activities_pkey`, `crm_links_pkey`, `crm_changes_pkey`; `pk_crm_account_projects` is explicitly named.

## `crm_accounts`

- `chk_crm_accounts_status`
- `fk_crm_accounts_owner_id` (`users.id`, `ON DELETE SET NULL`)
- `fk_crm_accounts_merged_into_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `idx_crm_accounts_active_lower_name` (unique, `lower(name)` where `archived_on IS NULL`)
- `idx_crm_accounts_active_lower_domain` (unique, `lower(domain)` where `domain IS NOT NULL AND archived_on IS NULL`)
- `idx_crm_accounts_status`
- `idx_crm_accounts_owner_id`
- `idx_crm_accounts_merged_into_id`
- `idx_crm_accounts_external_ref` (unique)

## `crm_contacts`

- `chk_crm_contacts_name_present`
- `chk_crm_contacts_email_not_blank`
- `fk_crm_contacts_account_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `fk_crm_contacts_owner_id` (`users.id`, `ON DELETE SET NULL`)
- `fk_crm_contacts_merged_into_id` (`crm_contacts.id`, `ON DELETE RESTRICT`)
- `idx_crm_contacts_account_id`
- `idx_crm_contacts_merged_into_id`
- `idx_crm_contacts_lower_last_name`
- `idx_crm_contacts_lower_first_name`
- `idx_crm_contacts_owner_id`
- `idx_crm_contacts_active_lower_email` (unique, `lower(email)` where `email IS NOT NULL AND archived_on IS NULL`)
- `idx_crm_contacts_external_ref` (unique)

## `crm_pipelines`

- `idx_crm_pipelines_name_unique` (unique)
- `idx_crm_pipelines_default_unique` (unique where `is_default`)

## `crm_pipeline_stages`

- `fk_crm_pipeline_stages_pipeline_id` (`crm_pipelines.id`, `ON DELETE RESTRICT`)
- `chk_crm_pipeline_stages_probability`
- `chk_crm_pipeline_stages_kind`
- `idx_crm_pipeline_stages_pipeline_position` (unique)
- `idx_crm_pipeline_stages_pipeline_name` (unique)
- `idx_crm_pipeline_stages_pipeline_id_id` (unique; target of the deals composite FK)

## `crm_deals`
`description` is `text` and stores the opportunity description/next-steps mapping.

- `fk_crm_deals_account_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `fk_crm_deals_contact_id` (`crm_contacts.id`, `ON DELETE RESTRICT`)
- `fk_crm_deals_pipeline_id` (`crm_pipelines.id`, `ON DELETE RESTRICT`)
- `fk_crm_deals_owner_id` (`users.id`, `ON DELETE SET NULL`)
- `fk_crm_deals_pipeline_stage` (`crm_pipeline_stages(pipeline_id, id)`, `ON DELETE RESTRICT`)
- `chk_crm_deals_probability`
- `idx_crm_deals_account_id`
- `idx_crm_deals_contact_id`
- `idx_crm_deals_pipeline_stage`
- `idx_crm_deals_owner_id`
- `idx_crm_deals_expected_close_on`
- `idx_crm_deals_closed_on`
- `idx_crm_deals_next_action_on_active` (where `archived_on IS NULL AND next_action_on IS NOT NULL`)
- `idx_crm_deals_external_ref` (unique)

## `crm_activities`

- `fk_crm_activities_account_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `fk_crm_activities_contact_id` (`crm_contacts.id`, `ON DELETE RESTRICT`)
- `fk_crm_activities_deal_id` (`crm_deals.id`, `ON DELETE RESTRICT`)
- `fk_crm_activities_author_id` (`users.id`, `ON DELETE SET NULL`)
- `chk_crm_activities_kind`
- `chk_crm_activities_channel`
- `chk_crm_activities_direction`
- `chk_crm_activities_visibility`
- `idx_crm_activities_account_occurred`
- `idx_crm_activities_contact_occurred`
- `idx_crm_activities_deal_occurred`
- `idx_crm_activities_author_id`
- `idx_crm_activities_archived_on`
- `idx_crm_activities_external_identity` (unique where both external columns are non-null)

## `crm_links`

- `fk_crm_links_account_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `fk_crm_links_contact_id` (`crm_contacts.id`, `ON DELETE RESTRICT`)
- `fk_crm_links_deal_id` (`crm_deals.id`, `ON DELETE RESTRICT`)
- `fk_crm_links_issue_id` (`issues.id`, `ON DELETE CASCADE`)
- `chk_crm_links_one_target`
- `idx_crm_links_account_issue_unique` (unique)
- `idx_crm_links_contact_issue_unique` (unique)
- `idx_crm_links_deal_issue_unique` (unique)
- `idx_crm_links_issue_id`

## `crm_account_projects`
`created_on` is `timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP`.

- `pk_crm_account_projects` (primary key `(account_id, project_id)`)
- `fk_crm_account_projects_account_id` (`crm_accounts.id`, `ON DELETE RESTRICT`)
- `fk_crm_account_projects_project_id` (`projects.id`, `ON DELETE CASCADE`)
- `idx_crm_account_projects_project_id_unique` (unique)

## `crm_changes`

- `chk_crm_changes_record_type`
- `idx_crm_changes_record_record_created`
- `crm_changes_append_only_guard()` (PL/pgSQL trigger function)
- `crm_changes_append_only` (BEFORE UPDATE OR DELETE trigger)

`crm_changes.user_id` intentionally has no foreign key. Core references (`users.id`,
`issues.id`, and `projects.id`) use integer columns because Redmine 7 stores those serial
primary keys as integer; CRM-owned primary and foreign keys use bigint.
