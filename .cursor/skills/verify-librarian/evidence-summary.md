# verify-librarian evidence summary

Per-run transcripts live under `evidence/runs/` (gitignored). This is the committed summary of the first full drive.

## Run

- run_id: `20261023T162134Z-2843`
- launch: `launch_ok` on isolated port, `VERIFY_MOCK_LLM=0` (a model key was present, so the LLM was live; Notion still mocked)
- doctor: `doctor_ok` after the inspector was taught to read the source `tools -> END` edge (compiled `get_graph()` only lists `tools -> tool_calling_llm`)
- drive: `helpers/drive.sh` for every mapped feature
- cleanup: scratch removed; `evidence/runs/20261023T162134Z-2843/SUMMARY.md` still present

## Per-feature results

| Feature | Harness | Result |
|---|---|---|
| Parse a book request | live `langgraph dev`, Notion mocked | ok. `I am looking for Atomic Habits` routed `llm->tools:search_library_page` then `write_to_notion`. Catalog returned live Sunnyvale HTML. Guard logged `blocked_live` for the pages URL and returned a mock 200. |
| Graph routing | live `langgraph dev`, Notion mocked | ok. Source has both `tools -> tool_calling_llm` and `tools -> END`. Compiled graph only shows the loop. Live `The Mom Test` run: `llm->tools:search_library_page` then `llm->end_or_text` (no second tool). |
| `write_to_notion` statuses | pytest, `requests` mocked | ok. `tests/test_write_to_notion_statuses.py` passed for `Available now`, `Not available`, `Not Available`, `All copies in use`. |
| `notion_database.get_pages` | pytest, `requests` mocked | ok. Pagination (`num_pages is None`) and finite `page_size` (`num_pages=5`). Import-time `print(get_pages())` stayed on the mock. |
| No-token-leak check | pytest, `requests` mocked | ok. `tests/test_no_token_leak.py` passed. |

## Stand-in setup this Cloud image needed

- `apt install python3.12-venv` because `python3 -m venv` failed with ensurepip missing. A normal developer machine with `python3-venv` already installed will not need that.
- Harness venv from `helpers/requirements.txt` (not a product requirements file).

## What the live path did not do

- No real `api.notion.com` socket. The guard intercepted the one `write_to_notion` POST.
- LLM was not mocked (`VERIFY_MOCK_LLM=0`). If a later environment has no model key, launch sets `VERIFY_MOCK_LLM=1` and the scripted model still emits `search_library_page`.
