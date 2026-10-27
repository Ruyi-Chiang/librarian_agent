# Graph routing

The compiled librarian graph starts at `tool_calling_llm`. `tools_condition` sends that node to `tools` when the model emitted tool calls, or to `END` when it did not. After `tools`, the only outgoing edge is `tools -> tool_calling_llm`. END happens only when the LLM stops calling tools. This feature proves those edges and that a live run takes LLM -> tools -> LLM -> END.

## Sub-features

- `llm-to-tools` — a catalog request produces a tool call and `tools_condition` routes to `tools`.
- `tools-to-llm` — the `tools -> tool_calling_llm` edge is present on the compiled graph.
- `llm-to-end` — a non-tool assistant message ends the turn via `tools_condition`.

## How to get to it (user POV)

- In Studio, send a book request. The first assistant step should be a tool call (catalog search and/or Notion write).
- After tools run, Studio shows another model step. The run ends when that model step has no tool calls.
- A chit-chat / out-of-scope line should be refused in text and end without tools.

## Driving it with langgraph dev

Preconditions:

- `helpers/launch.sh` completed; `helpers/doctor.sh` printed `doctor_ok`.
- Notion HTTP is mocked. The model is live when a real `OPENAI_API_KEY` exists, otherwise `VERIFY_MOCK_LLM=1`.

- **Source + compiled edges.** `helpers/drive.sh graph-routing` first runs `helpers/inspect_graph.py` (ChatOpenAI patched, no model call). Exit `0`. JSON has `source.has_tools_to_llm: true` and `source.has_tools_to_end: false` from `librarian.py` text. `compiled_has_tools_to_llm` is true. `compiled_has_tools_to_end` is false.
- **Live run.** The same helper POSTs `Please find The Mom Test at the library` to `/threads/{id}/runs/wait`. Exit `0`. `routing_trace` contains `llm->tools:...`.
- **Proof.** `graph-routing-edges.stdout.txt` and `graph-routing-run.stdout.txt` under `evidence/runs/<id>/`. The live path is tools back to the LLM, then `tools_condition` to `END` when the model stops calling tools.

## Gotchas

- `tools_condition` is the only conditional router, and it sits on `tool_calling_llm`, not on `tools`.
- If no usable model key is available, the scripted LLM still emits `search_library_page` then (if the loop runs) `write_to_notion`. The write hits the Notion mock, not `api.notion.com`.
- Inspecting `graph.get_graph()` in-process is how we pin the edges. It is not a substitute for the live `/runs/wait` drive.
