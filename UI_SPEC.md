# UI rebuild spec — Redmine idiom, usable daily (2026-09-09)

Owner verdict on v0.1.x: lists were a foreign grid that rendered as a wall of text, the dashboard had no
navigation, association columns were empty. The CRM must look and behave like the rest of Redmine and be
usable every day by a solo agency owner. Reference templates (copied from the running 7.0.1):
`/Users/zidiwang/tmp/redmine-crm/ref/issues-views.txt` (issues index, _list, sidebar, query form) and
`/Users/zidiwang/tmp/redmine-crm/ref/issue-show.txt` (issue show, render_tabs, context menu, base layout).
Design doc: `/Users/zidiwang/tmp/redmine-crm/redmine-crm-design.org`. Contract: `CONTRACT.md`.

## Daily jobs the UI must make fast (in order of frequency)
1. See what needs doing today: overdue / due-today next actions, stale open deals (no activity 14 d).
2. Log a call/note/message on a deal or contact in two clicks from its page.
3. Move a deal to the next stage (board drag or a stage select on the deal page).
4. Capture a new lead (contact + optional account + deal) in one form.
5. Look up a client: account page → contacts, open deals, timeline, linked Redmine projects/issues.
6. Slice the pipeline: deals list grouped by stage/owner/lead source with money totals (Redmine group-by + totals).
7. Find anything via the header search.

## Navigation
- Every CRM page renders `crm/shared/_nav.html.erb` directly under Redmine's header, before the page `h2`:
  Redmine `div.tabs` markup (`<div class="tabs"><ul><li><a class="selected">…`) with Dashboard, Accounts,
  Contacts, Deals, Board, Activities (staff/viewer); contractors see Dashboard, Accounts, Contacts, Activities.
  Admins additionally see a "Pipelines" tab. The current page's tab is `selected`.
- Top menu entry `CRM` stays. Page titles via `html_title`.

## Lists (accounts, contacts, deals, activities) — exactly Redmine's issues index shape
- `div.contextual` with `link_to sprite_icon('add', …), new_path, class: 'icon icon-add'` (staff only) and, on
  deals, a link to the board.
- `h2` = query name or list label; `form_tag(list_path, method: :get, id: 'query_form') { render 'queries/query_form' }`
  (core partial; our Query subclasses must satisfy it: `available_display_types`, `available_block_columns`,
  `groupable_columns`, `available_totalable_columns`, `default_totalable_names`, `css_classes`).
- Body: `render_query_totals(@query)`, then a `table.list.odd-even` built exactly like `issues/_list`:
  `column_header(query, column)` per inline column, `column_content(column, record)` per cell, grouped rows via
  a small local helper mirroring `grouped_issue_list` (`query.results(order: …)` + `query.result_count_by_group`),
  checkbox column + `link_to_context_menu`, `pagination_links_full`, `other_formats_links` with CSV.
- Row link: the record name column links to the record page (`column_content` does this when the column is
  the `name` column; implement `CrmQuerySupport#column_value`-style override in the Query subclasses or a
  `crm_column_content` helper that wraps names in `link_to`).
- Context menu: `crm/context_menus/{accounts,contacts,deals,activities}.html.erb` rendered by a
  `Crm::ContextMenusController` (routes `/crm/context_menus/<type>`), Redmine markup (`ul` of
  `context_menu_link`), actions: Edit (single), Archive, Restore (when archived), Set owner (submenu of active
  users), deals: Set stage (submenu), Set pipeline… no; activities: none besides Archive/Restore. Bulk actions
  POST to the existing `bulk` route with `ids[]`; the bulk action returns to `back_url`.
- Archived filter: query filter `archived` (default excluded).
- Contractors: fixed default query, no sidebar, no context menu, no CSV.
- Remove Tabulator from the lists (keep the vendored file for now; `crm.js` grid code becomes unused → delete
  it). Inline editing is out; editing happens on the record page and via the context menu (Redmine idiom).

## Record pages — Redmine issue-show shape
- `div.contextual` action menu: Edit (`icon icon-edit`), Archive/Restore, Merge into… (accounts/contacts, staff),
  New contact / New deal (accounts), New deal (contacts), Log activity anchor.
- `h2` with the name (+ Redmine `badge` for status/stage: e.g. `<span class="badge badge-status-open">`).
- `div.details` → `div.attributes` two-column rows (reuse `IssuesHelper#issue_fields_rows` by including
  IssuesHelper in CrmHelper — its output is generic `table.attributes`; or copy the tiny builder into CrmHelper as
  `crm_fields_rows`) for core fields, then `render_half_width_custom_fields_rows(record)`-style custom fields
  (CustomFieldsHelper has `render_half_width_custom_fields_rows`/`render_full_width_custom_fields_rows` taking any
  customizable object — verify signature in /home/redmine/redmine/app/helpers/custom_fields_helper.rb).
- Description via `textilizable(record, :description)`; attachments via `link_to_attachments record` (staff/viewer).
- Related sections, each an `h3` + `table.list` (Redmine style, no Tabulator): account → Contacts (name, email,
  job title), Deals (name, stage, amount for money holders, next action), Projects (linked Redmine projects with
  link + unlink for staff; "Link project" select form), Issues (linked issues + link form); contact → Deals,
  Activities; deal → Issues, Projects (via account) and a `Stage` select form (staff) that PUTs `move` (form, not
  JS). The deal's account and contact are links in the attributes grid and are not repeated as sections.
- Timeline: below, `div#history.journals` with Redmine journal markup (`div.journal`, `h4` with time + author,
  `div.wiki` body) listing activities and change rows newest first; a composer form at the top styled like the
  issue "Add notes" box (`fieldset` with kind select, occurred_at datetime field default now, body textarea,
  Submit) — one submit, redirect back with flash.
- History tab is not separate: change rows are journal entries with "Property: old → new" details like issue
  journals (`ul.details li`).

## Forms (new/edit)
- `labelled_form_for` inside `div.box.tabular` with `p` per field, custom fields via `render_custom_field_tag`
  loop (see core `issues/_attributes`), `p.buttons` submit; `error_messages_for`.

## Dashboard `/crm`
- Left column (`div.splitcontentleft`): boxes `div.box` with `h3` and `table.list`: "Overdue next actions",
  "Due today", "Stale open deals" (each row: deal link, account, stage, next action, date), "My open deals".
- Right column (`div.splitcontentright`): "New lead" form (staff) in a `div.box.tabular`; "Recent activities" list
  (journal style, 10 rows); pipeline totals per stage for money holders (small `table.list`).
- Contractors: their linked accounts, contacts, shared activities only.

## Board `/crm/deals/board`
- Keep SortableJS; markup as `div.crm-board` of `div.box` columns each with `h3` = stage name + count (+ total
  for money holders), cards `div.crm-card` with deal link, account, next action; CSS in crm.css tuned to
  Redmine's `.box` look. Open-stage columns flex to fit the viewport (`flex: 1 1 200px`, min 180px); won/lost
  columns are collapsed to a 150px count/total with a link to the filtered list; the board scrolls horizontally
  only when the columns cannot fit. Drag → PUT move (already works). Contractors 404.

## Admin pages
- `/crm/admin/pipelines`: Redmine admin layout (`layout 'admin'`), `table.list` of pipelines and their stages
  with edit/delete icons; forms in `div.box.tabular`.

## Locales
- All new strings in `config/locales/en.yml`; no "Translation missing" anywhere (grep proves it).

## Verification (orchestrator)
- Staging on thinkserver: http://100.96.236.17:10084 (admin/admin at first login → password change) with the
  imported Twenty data. Every page above is screenshotted and read; a page ships only when it looks like Redmine.
