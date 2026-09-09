# Changelog

All notable changes to `redmine_crm` are recorded here. Release tags are immutable; the supported Redmine range and migration state for each release are part of its deployment record.

## v0.1.1 — 2026-09-09

- Health receipt emits `counts` and `required_groups` keys correctly through the API builder.
- Deployed to redmine.trymaderight.com; Twenty import receipt: 11 accounts (Atlasguard merged into AtlasGuard), 32 contacts, 31 deals, 634 activities, 25,675,000 cents.

## v0.1.0 — 2026-09-09

- Added the Redmine CRM plugin foundation for global accounts, contacts, deals, pipelines, stages and activities.
- Added PostgreSQL-backed migrations, Redmine groups and roles, custom fields, saved views, explicit project and issue links, and archived-record lifecycle rules.
- Added the narrow Upwork feed contract, idempotent external identities, the Twenty import/export tasks, and the authenticated health receipt.
- Added GitHub Actions coverage for Redmine 7.0-stable, Ruby 4.0 and PostgreSQL 15.
