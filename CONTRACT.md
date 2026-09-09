# redmine_crm — implementation contract for parallel slices

The design is `/Users/zidiwang/tmp/redmine-crm/redmine-crm-design.org` (org-mode, 628 lines). It is the
specification; this file only pins the names the slices share so they can be written in parallel and
integrate without negotiation. When the design and this file disagree, follow the design and tell the
integrator.

## Environment
- Plugin root: `/Users/zidiwang/tmp/redmine-crm/redmine_crm` (mounted into the dev stack at
  `/app/plugins/redmine_crm`).
- Dev stack: `cd /Users/zidiwang/tmp/redmine-crm/dev && docker compose exec -T app sh -c 'cd /app && <cmd>'`.
  Redmine 7.0-stable (7.0.1) + Rails 8.1.3.1 + Ruby 4.0 + PostgreSQL 15. Databases `redmine_development`
  and `redmine_test` exist; default data is loaded. Useful commands inside the container:
  `bin/rails redmine:plugins:migrate`, `bin/rails runner '<ruby>'`, `RAILS_ENV=test bin/rails redmine:plugins:migrate`,
  `bin/rails test plugins/redmine_crm/test/<file>`. Core source is at `/app` (read-only for you), e.g.
  `app/models/query.rb`, `app/controllers/application_controller.rb`, `lib/plugins/acts_as_customizable`.
- Redmine 7 facts you must respect: `User.current` uses `ActiveSupport::CurrentAttributes` (no RequestStore gem);
  requests whose `params[:format]` is json/xml ignore the browser session (API key only); `SafeAttributes`
  silently drops unsafe keys; `Role#permissions` is serialized; core CSRF verification is skipped for
  json/xml formats — which is why browser mutations use extensionless routes (see config/routes.rb).

## Already written (do not rewrite; extend only if your slice says so)
- `init.rb`, `lib/redmine_crm.rb` — registration, `requires_redmine '7.0'..'7.9'`, one plugin Setting with
  keys `feed_contract_version`/`feed_last_success_at`, `project_module :crm { permission :view_crm_linked, {}, read: true }`,
  top menu, search type registration (`crm_accounts crm_contacts crm_deals crm_activities`).
- `lib/redmine_crm/access.rb` — `Crm::Access`: `capability(user)` → `:admin|:staff|:viewer|:feed|:contractor|:none`;
  `staff?` (admin or crm-staff), `viewer?`, `feed?`, `contractor?`, `reads_all?`, `staff_or_viewer_or_linked?`,
  `can_view_money?`, `can_write?`, `can_archive?`, `can_manage_queries?`, `contractor_project_ids(user)`,
  `contractor_role_ids`. Group names: `RedmineCrm::GROUP_STAFF/GROUP_VIEWER/GROUP_FEED`, role name
  `RedmineCrm::CONTRACTOR_ROLE_NAME`.
- `lib/redmine_crm/hooks.rb` — renders `crm/hooks/_project_account` and `crm/hooks/_issue_links` partials;
  adds `crm.css` on `Crm::*` controllers.
- `lib/redmine_crm/custom_fields_tabs.rb` — appends the three CRM custom-field tabs.
- `config/routes.rb` — COMPLETE route contract (API `.json/.xml` set + extensionless browser set). Controllers
  are namespaced `Crm::` (`app/controllers/crm/*_controller.rb`). Route helpers are prefixed `crm_`
  (e.g. `crm_accounts_path`, `crm_account_path(a)`, `crm_deals_board_path`, `crm_move_deal_path(d)`,
  `crm_api_accounts_path(format: 'json')`).
- `assets/javascripts/tabulator.js` (6.5.2), `assets/javascripts/sortable.js` (1.15.7), licenses beside them,
  `assets/stylesheets/tabulator_simple.css`. Plugin assets are served by Propshaft at
  `/assets/plugin_assets/redmine_crm/<file>`; in views use `javascript_include_tag('crm', plugin: 'redmine_crm')`.
- `config/locales/en.yml` — stub. The VIEWS slice owns this file; every other slice lists the keys it needs in
  its final report and uses `l(:key)` with keys prefixed `label_crm_`, `field_crm_`, `text_crm_`, `button_crm_`.

## Model names and files (MODELS slice owns app/models except *_query.rb)
Top-level classes (Redmine convention; STI custom-field lookup is `#{class}CustomField`):
`CrmAccount`, `CrmContact`, `CrmDeal`, `CrmPipeline`, `CrmPipelineStage`, `CrmActivity`, `CrmLink`,
`CrmAccountProject`, `CrmChange`, `CrmAccountCustomField < CustomField`, `CrmContactCustomField`, `CrmDealCustomField`.
Tables and columns exactly as the design's Domain model tables (`crm_accounts`, `crm_contacts`, `crm_deals`,
`crm_pipelines`, `crm_pipeline_stages`, `crm_activities`, `crm_links`, `crm_account_projects`, `crm_changes`).
Timestamps are `created_on`/`updated_on` (Redmine style). Concerns under `app/models/concerns/crm/`:
`Crm::Archivable` (`archived_on`, `archive!(user)`, `restore!(user)`, `default_scope`-free `active` scope),
`Crm::Auditable` (writes `CrmChange` rows from `saved_changes` and custom values; `record_type` is the class name),
`Crm::ActiveParentAssociation` (validation: merged parents reject every child write; archived-unmerged parents
accept activities only). Shared method contract every record model exposes:
- `self.visible(user)` scope (staff/viewer: all; contractor: linked scope per design; others: none);
  `visible?(user)`; `self.for_api(user)` = visible without archived unless `include_archived`.
- `archive!(user)`, `restore!(user)` (raise `ActiveRecord::RecordInvalid` on name/email/domain collisions).
- `attachments_visible?(user)`, `attachments_editable?(user)`, `attachments_deletable?(user)` (plugin rules).
- `self.search_result_ranks_and_ids(tokens, user, projects = nil, options = {})` and
  `self.search_results_from_ids(ids)` for accounts, contacts, deals, activities (visible scope; no attachment names).
- `safe_attributes` lists per design (money attrs only for `Crm::Access.staff?`; `external_ref`,
  `external_source`, `external_id` create-only).
- Services in `app/services/crm/`: `Crm::MoveDeal.call(deal:, stage:, user:, lock_version:)`,
  `Crm::Merge.call(source:, target:, user:)`, `Crm::CreateLead.call(params, user)`.
- Money: `CrmDeal#amount_cents` bigint, `currency` char(3) default USD; `weighted_cents` uses
  `COALESCE(deals.probability, stages.probability)`.

## Queries (QUERIES slice owns app/models/crm_*_query.rb, app/controllers/crm/queries_controller.rb, app/views/crm/queries)
`CrmAccountQuery`, `CrmContactQuery`, `CrmDealQuery`, `CrmActivityQuery < Query`, global (`project_id` nil),
`queried_class`, `available_filters`, `available_columns` (money columns only when `Crm::Access.can_view_money?(User.current)`),
`base_scope` = `queried_class.visible(User.current)` (+ archived filter), `results(options)`, `result_count`,
totals per currency. Custom-field filters/columns only from fields visible to the user; the CRM custom-field
classes make `visibility_by_project_condition` project-free.

## Controllers and API (CONTROLLERS slice owns app/controllers/crm/* except queries_controller, app/helpers/crm_helper.rb, app/views/crm/**/*.api.rsb)
`Crm::BaseController < ApplicationController`: `before_action :require_login`, capability precedence
(feed → 403 on everything except feed actions; contractor → 403 on any API-format request and on deals/board;
none → 404), `find_record` via `visible` scope (404), helper `crm_money?`, `accept_api_auth` per action as the
design's route table, SafeAttributes precheck returning 422 with forbidden keys, `lock_version` handling
(409 on `ActiveRecord::StaleObjectError`), duplicate external identity → 200 with existing record.
Controllers: `dashboard`, `accounts`, `contacts`, `deals` (incl. `board`, `move`, `lookup`), `activities`,
`links`, `account_projects`, `merges`, `feed`, `health`, `pipelines`, `stages` (admin), each with
`index/show/new/create/edit/update/archive/restore/bulk` where routed. Helper `CrmHelper`:
`crm_money(cents, currency)`, `crm_record_link(record)`, `crm_owner_name(user_id)` (display name only,
"deleted user" when absent), `crm_history_rows(record)` (money/hidden-cf redaction).

## Views and assets (VIEWS slice owns app/views/crm/** except *.api.rsb and crm/queries, assets/javascripts/crm.js, assets/stylesheets/crm.css, config/locales/en.yml)
Redmine `base` layout; sidebar via `render_sidebar_queries(CrmDealQuery, nil)` etc. for staff/viewer only.
Lists: Tabulator grid fed by a JSON data attribute (`data-crm-rows`) and posting per-row PATCHes to the
extensionless `update` route with `X-CSRF-Token` (`<meta name="csrf-token">` from Redmine layout) and
`lock_version`. Board: SortableJS columns → `PUT /crm/deals/:id/move` JSON body `{stage_id, lock_version}`.
Record pages: properties panel + timeline composer + tabs (Timeline, Contacts, Deals, Issues, Projects, Files,
History). Dashboard with New-lead form. Admin pipelines/stages pages. Merge confirmation page. Hook partials.
Keyboard: `/`, `g a`, `g c`, `g d`, `n`, Esc. Everything through `l()`.

## Tests (TESTS slice owns test/**)
Redmine style (`test/test_helper.rb` requires `../../../test/test_helper`); fixtures for CRM tables under
`test/fixtures/`; run with `bin/rails test plugins/redmine_crm/test`. Coverage list = design → Testing.

## Importer (IMPORT slice owns lib/tasks/*.rake, lib/redmine_crm/twenty_import.rb, lib/redmine_crm/export.rb)
`rake redmine:crm:import_twenty DIR=<csv dir> [MODE=diff]`, `rake redmine:crm:export DIR=`, `rake redmine:crm:setup`
(groups, role `CRM Contractor` with `view_crm_linked`, seed pipeline `Sales` + stages, seed custom fields).

## CI (CI slice owns .github/workflows/ci.yml, README.md, CHANGELOG.md, LICENSE)
GitHub-hosted: checkout redmine/redmine 7.0-stable, plugin into plugins/redmine_crm, Ruby 4.0, PostgreSQL 15
service, bundle install, db create/migrate + redmine:plugins:migrate (RAILS_ENV=test), run the tests.

## Rules
- Touch only the files your slice owns. Need something from another slice? Code against the names above and
  say so in your report; the integrator wires gaps.
- Verify your own slice boots: `bin/rails runner 'puts CrmAccount.count'` or the relevant command inside the
  container. Do not run the whole test suite; do not run formatters.
- No secrets, no network calls in code, PostgreSQL-only SQL is fine.
