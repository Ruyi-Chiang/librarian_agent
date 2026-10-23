# Parse a book request

A user asks for a book in plain language. The librarian graph turns that into a Sunnyvale Public Library catalog search and returns visible result text (title clues, call number, availability). The live path is `search_library_page` inside `librarian.py`. `parser.py` is the older standalone script that scrapes a `.call-number` node and runs a ReAct agent at import time; LangGraph does not load it.

## Sub-features

- `catalog-query` sends the user's title (or author/keyword) to `sunnyvale.bibliocommons.com` smart search.
- `result-cards` reads up to three `li.cp-search-result-item` nodes and returns their visible text.
- `standalone-parser` is `parser.py:get_call_number` plus the module-level agent. It is **not** the Studio surface.

## How to get to it (user POV)

- Start `langgraph dev` and open Studio against the local API, graph `librarian`.
- Reply to the greeting with a catalog request such as `I am looking for Atomic Habits`.
- Watch the assistant call `search_library_page` and come back with catalog text.
- Do not run `python parser.py` as the user path: import executes two `agent.run` calls immediately.

## Driving it with langgraph dev

Preconditions:

- `helpers/launch.sh` completed; `helpers/doctor.sh` printed `doctor_ok`.
- Notion guard is loaded (launch put `helpers/` on `PYTHONPATH`). The catalog host is not Notion and may be reached live.

- **Default verification (harness).** Run `helpers/drive.sh parse-book-request`. That POSTs a human message to `/threads/{id}/runs/wait` on this run's local API with `assistant_id=librarian` and content `I am looking for Atomic Habits`. Exit code `0`. Stdout JSON includes `search_library_page` in `tool_names` or `routing_trace`.
- **Proof.** `parse-book-request.stdout.txt` plus `parse-book-request.wait.json` under `evidence/runs/<id>/`. The wait payload's messages show a tool call to `search_library_page`.
- **Not a substitute.** Do not import `parser.py`. Do not treat a mocked-HTML unit test as this live feature.

## Gotchas

- `langgraph.json` wires only `./librarian.py:graph`. A green Studio run does not prove `parser.py` still works; it proves the graph's catalog tool.
- `parser.py` calls `agent.run(...)` at module import. Any `import parser` hits OpenAI and the catalog twice. Keep it out of pytest.
- `get_call_number` looks for `.call-number`; `search_library_page` looks for `cp-search-result-item`. They are different parsers.
- If no usable model key is in the environment, launch sets `VERIFY_MOCK_LLM=1`. The scripted model still emits a `search_library_page` tool call. Say so in the run notes when that happens.
- Empty catalog HTML (`No search results found.`) is a real catalog miss, not a harness skip. Record it and fail the journey if `search_library_page` was never called.
- Notion is mocked. A successful parse must not be "proven" by a new row in Ruyi's Book Tracker.
