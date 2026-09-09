# redmine_crm

`redmine_crm` is a Redmine plugin for accounts, contacts, deals, pipelines and an activity timeline. It stores ordinary Rails records in Redmine's PostgreSQL database and uses Redmine's users and SSO, groups and roles, custom fields, saved queries, attachments, search, REST API and backups. Twenty is a functional reference for the record table, kanban, record page, saved views and timeline; it is not a runtime dependency.

The plugin supports Redmine 7.0 through 7.9. Redmine 8 is not supported by this release. CRM records are archived rather than permanently deleted. The plugin does not add a datastore, a resident worker or a second identity system.

## Install

Install an immutable release tag into the Redmine plugin directory. Do not install a moving branch in production.

```sh
cd /path/to/redmine
# Replace v0.1.0 with the release selected for the deployment.
git clone --branch v0.1.0 --depth 1 \
  https://github.com/nick-maderight/redmine_crm.git plugins/redmine_crm

RAILS_ENV=production bundle exec rake redmine:plugins:migrate
# Restart the Redmine application so the plugin and its assets are loaded.
# Then create or reconcile the groups, role, pipeline and custom fields:
RAILS_ENV=production bundle exec rake redmine:crm:setup
```

In a managed Redmine image, run the migration during the normal startup migration gate, restart the application, and run the setup task as a separate, recorded step. A failed migration is a failed deployment; retain the previous plugin tag for rollback. The plugin requires PostgreSQL.

## Groups and roles

The exact group names are case-sensitive:

- **`crm-staff`**: reads and writes all CRM records, archives and restores records, manages links and attachments, saves and deletes CRM queries, and sees money.
- **`crm-viewer`**: reads all CRM records and authorized history, but cannot write, archive, restore, mutate attachments or see money.
- **`crm-feed`**: an API-only integration identity. It can perform the narrow external-reference lookups and feed creates described below. It cannot browse collections, search, read history or attachments, or widen visibility.
- **`CRM Contractor`**: a project membership role, not a group. It grants linked account, contact and shared-activity access only when the client project has the `crm` module enabled and the membership has `view_crm_linked`.

A Redmine administrator receives the staff capability, except that permanent deletion does not exist. Developer, Manager and Reporter memberships do not grant CRM access by themselves. A contractor never sees deals, money or change history, and cannot write. Group membership and contractor membership are separate capability branches; they are not combined.

The setup task creates or reconciles the three groups, the `CRM Contractor` role and its `view_crm_linked` permission, the default Sales pipeline and stages, and the CRM custom-field definitions. SSO group claims must map to the same Redmine group names. The feed service account is a direct `crm-feed` group member and must not be an SSO login user.

## Upwork feed

The feed client runs outside Redmine from the existing `upwork-autosync` deployment. The plugin does not start a daemon or own a second feed datastore. The deployed units are `crm-feed.service` and `crm-feed.timer`; their output goes to journald.

The service uses a Redmine API key belonging to a direct `crm-feed` group member. Feed writes are intentionally narrow and idempotent:

- contacts are resolved by `external_ref` (`upwork:client:<id>`) and created only when that identity is absent;
- deals are resolved or created by their external identity and new deals are forced to the `New` stage;
- activities use the `(external_source, external_id)` pair as their idempotency key and are staff-only;
- a duplicate identity returns the existing record, and a merged identity follows its survivor;
- the feed does not create accounts, move stages, create issues or receive money fields.

The feed pins the contract version and fails closed when the version is absent or mismatched. Key rotation uses a temporary direct `crm-feed` user; never add this group by hand to an SSO user whose next login would replace its group list.

## Twenty import and export

The Twenty importer is a one-shot rake task, not a user-facing CSV import:

```sh
RAILS_ENV=production bundle exec rake redmine:crm:import_twenty DIR=/path/to/csv
# A later run can import only absent identities and records:
RAILS_ENV=production bundle exec rake redmine:crm:import_twenty DIR=/path/to/csv MODE=diff
```

The accepted cohort is the manual, API and linked data: Twenty-derived accounts and contacts, all approved opportunities and retained communications, plus the Redmine Client-field accounts. Rows are keyed by their external references; activities are keyed by `(external_source, external_id)`. A diff run is idempotent and produces a verification receipt with provenance and counts. Email-derived rows, orphan attachments, blank project rows and the email-sync objects remain in the archived Twenty dump. Email ingestion is out of scope.

The companion export task writes versioned, legible JSON with completeness counts and the applicable records, links, custom fields, saved queries, history and attachment metadata. Money follows the caller's normal redaction policy.

## Health

`GET /crm/health.json` is an authenticated operational check for a Redmine administrator or a `crm-staff` member. Authenticate it with a Redmine API key. Anonymous, viewer and feed callers are rejected.

The receipt reports schema and asset readiness, CRM row counts, the latest Upwork activity and freshness status, the pinned feed contract version and last successful feed timestamp, required-group status, and whether the default pipeline and first open stage are usable. It reads the feed settings as one pair and never writes them. It reports `not_ready` when the feed is not configured or freshness cannot be established; it never includes API keys or other secrets.

## No CRM project

The CRM is globally scoped and is **not a Redmine project**. CRM record tables have no `project_id`, and installation does not create a CRM project container, project menu or project settings surface. Projects and issues are referenced only through explicit, authorized links:

- `crm_account_projects` links an account to an existing client project;
- `crm_links` links an account, contact or deal to an existing Redmine issue.

Project membership alone never grants CRM visibility. A contractor must have the `CRM Contractor` role, the `view_crm_linked` permission and an enabled `crm` module on that client project; the linked-record scope then determines what is visible. Staff and viewers use the global CRM surface, while contractors use the global `/crm` surface with their linked scope.

## License

Copyright (C) 2026 Made Right Software.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version. See `LICENSE` for the complete text.
