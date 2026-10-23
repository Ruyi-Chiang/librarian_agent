---
name: verify-librarian
description: Drive the librarian LangGraph agent (langgraph.json -> librarian.py:graph) and its mocked Notion/pytest checks. Use when proving catalog parse, graph routing, Notion write/query, or the no-token-leak test after a change.
---

# Verify librarian

Project-local control skill for agents that must prove a change against this app. The primary surface is LangGraph Studio / `langgraph dev` (graph name `librarian`). There is no in-repo web UI. Notion is an external store and is **never** contacted live by this skill.

Interview (do not invent past this):

| Question | This repo |
|---|---|
| Surface | Primary: LangGraph Studio against `langgraph dev` (graph `librarian` in `langgraph.json`). Secondary: pytest. `parser.py` is an older standalone catalog script and is **not** loaded by the graph. |
| Run | `langgraph dev --no-browser` from the repo root after the verify venv is installed. Ready = `GET /ok` on the local API (default Studio port is 2024; this harness picks an isolated port). Needs dummy `NOTION_TOKEN` / `NOTION_DATABASE_ID` so `librarian.py` can import. Model key optional (see Gotchas / Launch). |
| Drive | Live HTTP to the local LangGraph API for parse + graph routing (Notion mocked in-process). Pytest with `requests` mocked for Notion writes, `get_pages`, and the token-leak check. |
| Observe | HTTP `/ok`, run `messages` / routing trace, compiled graph edges, pytest stdout/exit, Notion-guard log (mocked intercepts only). |
| Isolate | Yes: unique `VERIFY_RUN_ID`, scratch under `/tmp/verify-librarian-<id>`, isolated port. Do not start a second server on the same port. |

## Hard rule: no live Notion

Never call `api.notion.com`. Never write to Ruyi's real Notion database. A live Notion write is allowed only against a dedicated test database she provides, and **none exists today**. This skill therefore always intercepts Notion HTTP and returns a mock. There is no escape hatch in the helpers. Do not `curl` Notion. Do not export a real `NOTION_TOKEN` into the langgraph child. Do not import `notion_database.py` without patching `requests` first (its module body calls `get_pages()`).

## Mapped features (live vs pytest)

| Feature | File | Drive |
|---|---|---|
| Parse a book request | [features/parse-book-request.md](features/parse-book-request.md) | **live** `langgraph dev`, Notion mocked |
| Graph routing | [features/graph-routing.md](features/graph-routing.md) | **live** `langgraph dev`, Notion mocked |
| `write_to_notion` statuses | [features/write-to-notion.md](features/write-to-notion.md) | **pytest**, `requests` mocked |
| `notion_database.get_pages` | [features/get-pages.md](features/get-pages.md) | **pytest**, `requests` mocked |
| No-token-leak check | [features/no-token-leak.md](features/no-token-leak.md) | **pytest**, `requests` mocked |

Read the feature map before claiming coverage beyond the feature you drove.

## Launch

Long-lived local API. Launch installs an isolated venv (if needed), opens scratch, and starts `langgraph dev` with the Notion guard on `PYTHONPATH`.

```bash
.cursor/skills/verify-librarian/helpers/launch.sh
```

`launch.sh` mints a new `VERIFY_RUN_ID` unless one is already exported, then writes `/tmp/verify-librarian.last-run`. Later `doctor.sh` / `drive.sh` / `cleanup.sh` reuse that id when unset. Concurrent runs must export distinct `VERIFY_RUN_ID` values. A second launch against a live pid restores the recorded port from `langgraph.port` and does not allocate a new one. `cleanup.sh` refuses (and does not `rm -rf`) when scratch isolation fails.

Host note: `python3 -m venv` must work. On Debian/Ubuntu that is the `python3-venv` / `python3.12-venv` package. A stand-in Cloud image that lacks it must install that package; a laptop with a working venv does not.

What it does:

1. Creates `VERIFY_SCRATCH=/tmp/verify-librarian-$VERIFY_RUN_ID` and `evidence/runs/$VERIFY_RUN_ID/` at the repo root.
2. Ensures `.venv` exists and installs [helpers/requirements.txt](helpers/requirements.txt) (harness-only; not a product requirements file).
3. Exports dummy Notion credentials (never a real integration) and `VERIFY_NOTION_GUARD_LOG`.
4. If `OPENAI_API_KEY` is missing or is an obvious test stub, sets `VERIFY_MOCK_LLM=1` so `helpers/sitecustomize.py` scripts the model. If a real key is present, the live model is used.
5. Starts `langgraph dev --no-browser --host 127.0.0.1 --port <isolated>` with `PYTHONPATH` pointing at `helpers/` so `sitecustomize.py` loads.

Ready when the script prints `launch_ok` and `GET /ok` on that port succeeds. Teardown is Cleanup (kill only that pid).

Two verification runs may proceed side by side when each has its own `VERIFY_RUN_ID` and port. They share the repo checkout; they must not share a port or scratch directory.

## Doctor

Read-only. Run after launch and again whenever a drive looks wrong.

```bash
.cursor/skills/verify-librarian/helpers/doctor.sh
```

Pass means all of:

- `.venv/bin/python` exists and is Python >= 3.11
- `langgraph`, `langchain_openai`, `requests`, `bs4`, `pytest` import
- scratch marker from this run exists
- the pid in `$VERIFY_SCRATCH/langgraph.pid` is alive
- `GET /ok` on this run's URL succeeds
- `/assistants` or `/info` is reachable and names `librarian`
- `librarian.py` still contains both `tools -> tool_calling_llm` and `tools -> END`; compiled `get_graph()` still lists the loop edge

If doctor fails, relaunch or stop. Do not "fix" it by pointing the graph at a real Notion database.

## Drive

Prefer helpers. Live features hit the local LangGraph API; Notion features stay in pytest.

```bash
.cursor/skills/verify-librarian/helpers/drive.sh parse-book-request
.cursor/skills/verify-librarian/helpers/drive.sh graph-routing
.cursor/skills/verify-librarian/helpers/drive.sh write-to-notion
.cursor/skills/verify-librarian/helpers/drive.sh get-pages
.cursor/skills/verify-librarian/helpers/drive.sh no-token-leak
.cursor/skills/verify-librarian/helpers/drive.sh all
```

Stable handles: assistant id `librarian`, tool names `search_library_page` and `write_to_notion`, status strings `Available now`, `Not available`, `Not Available`, `All copies in use`, pytest files `tests/test_write_to_notion_statuses.py`, `tests/test_get_pages.py`, `tests/test_no_token_leak.py`.

Manual live equivalent (only after launch+doctor; still Notion-mocked):

```bash
base="$(.cursor/skills/verify-librarian/helpers/doctor.sh >/dev/null; python3 -c 'print("see langgraph.port")')"
# Prefer the helper. A raw POST looks like:
# POST $base/threads
# POST $base/threads/$THREAD/runs/wait
#   {"assistant_id":"librarian","input":{"messages":[{"role":"human","content":"I am looking for Atomic Habits"}]}}
```

Never replace those URLs with `api.notion.com`.

## Evidence

Proof root (survives cleanup):

`evidence/runs/<VERIFY_RUN_ID>/`

That directory is gitignored. Commit only a short summary (`.cursor/skills/verify-librarian/evidence-summary.md`), not per-run transcripts.

Each drive writes:

- `<step>.stdout.txt`, `<step>.stderr.txt`, `<step>.meta.txt` (`command=`, `exit=`)
- live runs also write `*.wait.json`
- an append-only `SUMMARY.md` listing every feature driven in this run

Standards:

- Drive the user path (Studio-equivalent HTTP) or the named pytest file. Do not treat an in-process `graph.invoke()` as the live parse/routing proof.
- Capture the command and the resulting state (exit, routing_trace / pytest result), not only the last line.
- Notion side effects are proven through mocked `requests.post` assertions, never through a page on Ruyi's board.
- `helpers/sitecustomize.py` is the production-boundary mock for live runs. Pytest patches `requests` the same way. Dry-run is not a thing here: if a helper ran, it either mocked Notion or it failed closed.

## Cleanup

```bash
.cursor/skills/verify-librarian/helpers/cleanup.sh
```

Kills only the `langgraph` pid recorded for this run and deletes `VERIFY_SCRATCH`. Does not delete `VERIFY_EVIDENCE`. After cleanup, confirm `evidence/runs/<VERIFY_RUN_ID>/SUMMARY.md` still exists.

## Helpers

All scripts are executable. Source `common.sh`; invoke the others as commands from the repo root.

```bash
.cursor/skills/verify-librarian/helpers/launch.sh
.cursor/skills/verify-librarian/helpers/doctor.sh
.cursor/skills/verify-librarian/helpers/drive.sh all
.cursor/skills/verify-librarian/helpers/cleanup.sh
```

`helpers/sitecustomize.py` is not invoked directly; launch puts its directory on `PYTHONPATH` so the langgraph child loads it. `helpers/inspect_graph.py` and `helpers/drive_langgraph.py` are used by `drive.sh` / `doctor.sh`.

Keep the map honest with `/maintain-verification-skill` (edit only this skill directory; never edit product code to make a journey pass).
