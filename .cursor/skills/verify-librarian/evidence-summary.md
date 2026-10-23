# verify-librarian evidence summary

Per-run transcripts live under `evidence/runs/` (gitignored). This is the committed summary of the post-review drive.

## Run

- run_id: `20261023T173526Z-4141`
- launch: `launch_ok` on isolated port, `VERIFY_MOCK_LLM=0` (a model key was present, so the LLM was live; Notion still mocked)
- reuse: a second `launch.sh` printed `reused_pid=4206` and kept port `40887`
- doctor: `doctor_ok`
- drive: `helpers/drive.sh all` — every mapped feature ok
- cleanup: scratch removed; `evidence/runs/20261023T173526Z-4141/SUMMARY.md` still present

## Per-feature results

| Feature | Harness | Result |
|---|---|---|
| Parse a book request | live `langgraph dev`, Notion mocked | ok. `I am looking for Atomic Habits` routed `llm->tools:search_library_page` then `write_to_notion`. Guard logged `blocked_live` for the pages URL and returned a mock 200. |
| Graph routing | live `langgraph dev`, Notion mocked | ok. Source has both `tools -> tool_calling_llm` and `tools -> END`. Compiled graph only shows the loop. Live `The Mom Test` run: `llm->tools:search_library_page` then `llm->end_or_text`. |
| `write_to_notion` statuses | pytest, `requests` mocked | ok. `tests/test_write_to_notion_statuses.py` passed. |
| `notion_database.get_pages` | pytest, `requests` mocked | ok. `tests/test_get_pages.py` passed. |
| No-token-leak check | pytest, `requests` mocked | ok. `tests/test_no_token_leak.py` passed. |

## Review-fix probes (same helpers, not a mapped feature)

- Isolation-fail cleanup: `VERIFY_EVIDENCE` under scratch → exit 2, proof file kept.
- Launch reuse: live dummy pid + recorded port `54321` was kept when a second launch ran with a different `VERIFY_LANGGRAPH_PORT`.

## Stand-in setup this Cloud image needed

- `apt install python3.12-venv` because `python3 -m venv` failed with ensurepip missing. A normal developer machine with `python3-venv` already installed will not need that.

## What the live path did not do

- No real `api.notion.com` socket. The guard intercepted the `write_to_notion` POST.
- LLM was not mocked (`VERIFY_MOCK_LLM=0`).
