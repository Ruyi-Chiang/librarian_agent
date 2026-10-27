# librarian verification map

This directory is the maintained source for verifying user-facing behavior of the librarian LangGraph agent. Read this index before driving, then use the matching feature file.

## Baseline preconditions

- Launch with `helpers/launch.sh` so `.venv` exists, scratch is isolated, and `langgraph dev` is up with Notion mocked.
- Run `helpers/doctor.sh` and require `doctor_ok` before any live drive.
- Set unique `VERIFY_RUN_ID` for concurrent runs.
- Never export a real Notion token into the langgraph child. Never call `api.notion.com`.
- Do not `import parser` or `import notion_database` outside the documented pytest path. `parser.py` runs two catalog agents at import. `notion_database.py` calls `get_pages()` at import.

## Driving conventions

- Start every live recipe from launch+doctor.
- Prefer `helpers/drive.sh <feature-id>` or `helpers/drive.sh all`.
- Live features (parse, graph routing) go through the local LangGraph API. Notion features stay in pytest with `requests` mocked.
- Restoration means `helpers/cleanup.sh`. Do not remove proof artifacts under `evidence/runs/`.

## Proof and skip reporting

- Live proof includes the HTTP wait payload or routing trace, plus exit code.
- Pytest proof includes the node id, stdout, and exit code.
- Record the feature ID with every artifact under `evidence/runs/<VERIFY_RUN_ID>/`.
- A missing model key is not a skip: launch sets `VERIFY_MOCK_LLM=1` and the scripted model must still route to tools.
- A live Notion write is not an allowed fallback. If the guard is not loaded, stop.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features`
2. `How to get to it (user POV)`
3. `Driving it with <harness>`
4. `Gotchas`

## Features

- [Parse a book request](./parse-book-request.md) — **live** `langgraph dev` (Notion mocked). Catalog parse via the graph tool; `parser.py` is the older standalone script.
- [Graph routing](./graph-routing.md) — **live** `langgraph dev` (Notion mocked). LLM to tools, tools back to the LLM, and END when the LLM stops calling tools.
- [Write to Notion](./write-to-notion.md) — **pytest**, `requests` mocked. One write per status value.
- [Query Notion pages](./get-pages.md) — **pytest**, `requests` mocked. `notion_database.get_pages`.
- [No token leak](./no-token-leak.md) — **pytest**, `requests` mocked. `tests/test_no_token_leak.py`.

Out of this skill's drive surface: the separate `librarian-agent-evals` repo, any hosted Studio cloud deployment, and a live write to Ruyi's Book Tracker. Do not treat those as mapped features here.
