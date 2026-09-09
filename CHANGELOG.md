# Changelog

All notable changes to `redmine_crm` are recorded here. Release tags are immutable; the supported Redmine range and migration state for each release are part of its deployment record.

## v0.1.5 - 2026-09-09

- Browser mutations follow Redmine's form contract: create/update/move/archive/restore and context-menu bulk
  actions redirect back with a flash ("2 deals updated", "Updated successfully."); stale `lock_version`
  becomes a flash error instead of a raw 409; `ids[]`-only bulk submits are honoured (previously discarded
  when no per-record hash was present). API and board-drag JSON responses unchanged. Integration tests added.

## v0.1.4 - 2026-09-09

- UI rebuilt in Redmine's own idiom: CRM tab bar under the header; lists are Redmine query tables (filters,
  options, group-by with per-group money totals, sort, context menu, bulk archive/restore/owner/stage, CSV);
  record pages are issue-style (action menu, status badge, two-column attributes, custom fields, description,
  related tables, attachments, journal timeline with composer and named old/new values, "Show all" history);
  two-column dashboard (overdue / due today / stale / my open deals, new-lead form, pipeline totals, recent
  activities); board fits the viewport with won/lost columns collapsed to a count and a list link; pipelines
  under the admin layout. Tabulator removed. Money renders as `USD 57,500.00`; enums and statuses humanized.
- Contractors never see deals anywhere: dashboard activity context, activity list column and filter, related
  tables; regression tests added.
- v0.1.2: API builders emit `lock_version`; link history names projects; imports run as an admin actor.
- v0.1.3: Tabulator stylesheet loaded on CRM pages (superseded by the rebuild).

## v0.1.1 — 2026-09-09

- Health receipt emits `counts` and `required_groups` keys correctly through the API builder.
- Deployed to redmine.trymaderight.com; Twenty import receipt: 11 accounts (Atlasguard merged into AtlasGuard), 32 contacts, 31 deals, 634 activities, 25,675,000 cents.

## v0.1.0 — 2026-09-09

- Added the Redmine CRM plugin foundation for global accounts, contacts, deals, pipelines, stages and activities.
- Added PostgreSQL-backed migrations, Redmine groups and roles, custom fields, saved views, explicit project and issue links, and archived-record lifecycle rules.
- Added the narrow Upwork feed contract, idempotent external identities, the Twenty import/export tasks, and the authenticated health receipt.
- Added GitHub Actions coverage for Redmine 7.0-stable, Ruby 4.0 and PostgreSQL 15.
