# Pippa next: task list

Branch `claude/pippa-next`, plan in [pippa-next-architecture.md](pippa-next-architecture.md). Local commits only; push
and PR only on explicit request.

## Tool surface (target)

Pi's own: `read` (documents return text in the same call), `bash`, `write`; web: `web_search`, `fetch_content`.

Pippa's runtime tools (pippa-tools.ts): `search_files`, `list_folder`, `move_files` (destination `trash` moves to the
Trash), `remember`.

Pippa's MCP tools (in the app process): `calendar_read`, `reminders_read`, `mail_search`, `mail_read`, `photos_search`,
`front_read`, `read_document`, `calendar_add`, `reminder_add`, `mail_draft`, `prepare_files`.

Dropped: `applescript`, `pippa_more_tools` and tool-scope, `save_skill`, `make_chart`, `fill_pdf`, `move_to_trash`
(merged), pippa-context (handover and quiet summaries; Pi compacts), the draft-only lane.

## Steps

- [x] Audit and plan
- [ ] Runtime tools: fact-shaped results (sorted, full timestamps, at most 20, newest marked), `read` returns document
      text, drop the tools above, tests updated
- [ ] MCP: drop chart and form fill, `structuredContent` on card tools, tool list trimmed
- [ ] PiRPC: `toolEnded` carries the structured result
- [ ] Launch: short system prompt (under 300 tokens), fixed tool list, no keyword routing
- [ ] New app target: menu bar, hotkey, pill, chat window with sidebar (Pi sessions), composer with file drop and
      front-app chip, cards, stop, permissions on demand
- [ ] First run: one card (download for this Mac, or online AI); settings: AI, permissions, updates
- [ ] Delete old UI, routers, LocalEngine, SourceFidelity sentence removal, snapshot harness, old checks
- [ ] Checks: behavior only; CI split (fast PR gate)
- [ ] Docs: development.md, README; one ROADMAP; measurements archived
- [ ] Acceptance: the five tasks in the plan
