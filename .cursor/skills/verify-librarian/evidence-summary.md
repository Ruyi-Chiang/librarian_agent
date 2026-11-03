# verify-librarian evidence summary

Per-run transcripts live under `evidence/runs/` (gitignored). This is the committed summary of the post-tip-map drive on `main` at SHA `5e8353c9c0a28abb2037f765b25c3c7d8d8c0a7a`.

## Run

- run_id: `20261102T172955Z-2310`
- launch: `launch_ok` on isolated port `60401`, `VERIFY_MOCK_LLM=0` (a model key was present, so the LLM was live; Notion still mocked)
- reuse: a second `launch.sh` printed `reused_pid=2447` and kept port `60401`
- doctor: `doctor_ok`
- drive: `helpers/drive.sh all` — every mapped feature ok
- cleanup: scratch removed; `evidence/runs/20261102T172955Z-2310/SUMMARY.md` still present

## Per-feature results

| Feature | Harness | Result |
|---|---|---|
| Parse a book request | live `langgraph dev`, Notion mocked | ok. First human message was the catalog request `I am looking for Atomic Habits` (no greeting step). Routed `llm->tools:search_library_page` then `write_to_notion`. Guard logged `blocked_live` for the pages URL and returned a mock 200. |
| Graph routing | live `langgraph dev`, Notion mocked | ok. Loop-only routing after PR #10: source and compiled graph keep `tools -> tool_calling_llm` (`has_tools_to_llm` / `compiled_has_tools_to_llm` true; `tools_targets: ["tool_calling_llm"]`). Live `The Mom Test` run: `llm->tools:search_library_page` then `llm->end_or_text`. |
| `write_to_notion` statuses | pytest, `requests` mocked | ok. `tests/test_write_to_notion_statuses.py` passed. |
| `notion_database.get_pages` | pytest, `requests` mocked | ok. `tests/test_get_pages.py` passed. |
| No-token-leak check | pytest, `requests` mocked | ok. `tests/test_no_token_leak.py` passed. |

## Stand-in setup this Cloud image needed

- `apt install python3.12-venv` because `python3 -m venv` failed with ensurepip missing. A normal developer machine with `python3-venv` already installed will not need that.

## What the live path did not do

- No real `api.notion.com` socket. The guard intercepted the `write_to_notion` POST.
- LLM was not mocked (`VERIFY_MOCK_LLM=0`).
- `initial_state` greeting in `librarian.py` was not part of the live path; the compiled graph does not wire it in.
