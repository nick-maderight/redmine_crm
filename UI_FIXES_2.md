# UI fix round 2 — defects seen in staging screenshots (2026-09-09)

Staging: http://100.96.236.17:10084 (admin / staging-admin-2026). Every item below was observed in a real
browser screenshot. Fix the cause, re-sync, re-verify with a real render (curl HTML check is not enough for
layout items — use `ssh magicserver@thinkserver` + curl only for markup, and describe what you changed).

## RECORDS (crm-ui-rebuild-2 files: show/edit/new/_form templates, crm_fields_helper, shared/_timeline, _history)
R1. Attribute rows are stacked (label line, value line) instead of Redmine's two-column label/value layout.
    Redmine scopes `.attributes .attribute .label/.value` CSS under `div.issue`. Wrap the details block as
    `<div class="issue details">` (like issues/show) so core CSS applies; keep `.splitcontent` left/right.
R2. Owner shows "Deleted user" when owner_id is nil → show "-" (check nil before crm_owner_name).
R3. Stage change journal shows ids ("Stage: 4 → 1") → resolve CrmPipelineStage names for the `stage_id`
    property (and pipeline_id, account_id, contact_id, owner_id, deal_id → names) in the history detail renderer.
R4. "Files" section renders a bare `<input type=file>` with no form or submit → remove it from show pages.
    Attachments upload belongs on the edit form: `render :partial => 'attachments/form', :locals => {:container => @record}`
    inside the labelled form, and the controller `save_attachments(params[:attachments])` + `render_attachment_warning_if_needed`
    (verify the update/create actions already do this or add it — controllers are yours to touch for this only).
R5. Timeline is unbounded: Heesu Kim account renders 118 journals (36k px page). Show the newest 25 with a
    "Show all N" link (`?history=all`) that renders everything; the journals list stays newest first.
R6. Activity show page repeats its own body inside its timeline (the activity is in its own history) → the
    activity page timeline shows only change rows, not the activity itself.
R7. New/edit deal form: the Account, Pipeline, Stage and Owner selects have NO labels (empty label). Every
    field needs its label (use `f.select :account_id, ..., :label => :field_crm_account` etc.).
R8. Deal form asks for "Amount cents". Users enter money: label "Amount", virtual attribute `amount` (decimal,
    2 places) on CrmDeal that reads/writes amount_cents; permit `amount` in safe attributes; keep amount_cents
    for API. Show page: one "Amount" row "USD 57,500.00" (drop the separate Currency row; currency stays
    a form field beside Amount).
R9. Deal "Stage" section: replace the h3 + boxed form with a compact inline form in the `.contextual` area or
    directly under the attributes: `Stage: [select] [Save]` on one line (fieldset-less). Remove the odd empty
    grey vertical bars that appear left of each section (they come from empty `.box`/`fieldset` wrappers —
    find and delete them).
R10. Record page `h2` badge: use Redmine's `badge badge-status-open`/`badge-status-closed` classes for
    stage kind / status so it reads like an issue status badge.

## LISTS (crm-ui-rebuild-1 files: shared/_list, index templates, queries, crm_helper, context menus)
L1. Deals totals render as a Ruby hash: `Amount: {"USD" => 12400000}`. Render per-currency money:
    `USD 124,000.00` (join multiple currencies with ", "). Same for weighted amount. Group total rows show
    `Amount: 0` — the per-group totals are computed wrong; fix so each group total equals the sum of its rows.
L2. Amount column shows raw cents (5750000) with a separate Currency column → single Amount column formatted
    `USD 57,500.00` (money helper `crm_money` exists in dashboard/board — reuse); drop Currency from default
    columns (keep available).
L3. Status values render raw (`active_client`, `prospect`) → humanized via locale keys
    (`label_crm_account_status_<value>`; add keys to app/views/crm/LOCALE_KEYS_LISTS.txt for the locale owner,
    or if the key exists use it). Same for activity kind/channel/direction/visibility and deal stage kind.
L4. Contact column in activities list shows last name only ("Kim", "Jean") → full name (first + last).
L5. Redmine's top menu highlights "Activity" on /crm/activities (and activity show) because the controller is
    named activities. Set `menu_item :crm` in Crm::BaseController (all CRM controllers) so the CRM top-menu item is
    the current one everywhere. (This file is shared — you own this single line change; tell the others.)
L6. Deals list default sort is next_action_on asc with nulls first → sort `updated_on desc` by default; keep
    next action date sortable.
L7. Next action column shows raw `FOLLOW_UP` (imported Twenty enum) — display humanized (`Follow up`) via a tiny
    formatter in column content for next_action (titleize with underscores → spaces) — display only, data untouched.

## DASHBOARD / BOARD / CSS / LOCALES (crm-ui-rebuild-3 files)
D1. Dashboard is one column; spec says two: left `div.splitcontentleft` = Overdue, Due today, Stale, My open
    deals; right `div.splitcontentright` = New lead form, Pipeline totals, Recent activities (10, body capped 280).
    Boxes at half width; "No matching deals" nodata stays.
D2. Board overflows the page horizontally (7 columns, Negotiation cut off). Make `.crm-board` a horizontally
    scrolling flex container (`overflow-x: auto`, columns `flex: 0 0 260px`), and stop the huge empty vertical
    space (page is 2500px tall with 6 cards) — remove min-height on columns or cap to content + 200px.
D3. Board cards show raw `FOLLOW_UP` → humanize same as L7 (share a helper `crm_humanize_enum` in crm_helper —
    coordinate: LISTS owns crm_helper; ask them via hub to add `crm_humanize_enum(value)` and use it).
D4. Recent activities on dashboard show "Redmine Admin" as author for imported messages; show the activity
    subject (which holds the sender for messages) as the journal heading instead of the author when kind is
    message: "Message from Nick Wang" / "Note by Redmine Admin".
D5. Locales: add every key the other slices list in app/views/crm/LOCALE_KEYS_*.txt (status/kind/channel
    humanization keys), and `label_crm_show_all_history`. Grep the rendered staging pages for
    "Translation missing" at the end.

## Verification for everyone
Re-sync (rsync your files + cp into active + supervisorctl restart puma), then fetch your pages with the
curl session and confirm the markup change for each item id above. Report per item id: fixed + evidence.
