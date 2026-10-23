# Graph routing

The compiled librarian graph starts at `tool_calling_llm`. `tools_condition` sends that node to `tools` when the model emitted tool calls, or to `END` when it did not. After `tools`, today's product code adds **both** `tools -> tool_calling_llm` and `tools -> END`. This feature proves those edges still exist and that a live run actually takes LLM -> tools (and then whatever the double edge does). Do not "fix" the double edge in a verification PR.

## Sub-features

- `llm-to-tools` — a catalog request produces a tool call and `tools_condition` routes to `tools`.
- `tools-to-llm` — the `tools -> tool_calling_llm` edge is present on the compiled graph.
- `tools-to-end` — the contradictory `tools -> END` edge is also present. Document it; do not delete it here.
- `llm-to-end` — a non-tool assistant message ends the turn via `tools_condition`.

## How to get to it (user POV)

- In Studio, send a book request. The first assistant step should be a tool call (catalog search and/or Notion write).
- After tools run, Studio shows either another model step or the run completing. Today's graph can do both because `tools` has two unconditional outgoing edges.
- A chit-chat / out-of-scope line should be refused in text and end without tools.

## Driving it with langgraph dev

Preconditions:

- `helpers/launch.sh` completed; `helpers/doctor.sh` printed `doctor_ok`.
- Notion HTTP is mocked. The model is live when a real `OPENAI_API_KEY` exists, otherwise `VERIFY_MOCK_LLM=1`.

- **Source + compiled edges.** `helpers/drive.sh graph-routing` first runs `helpers/inspect_graph.py` (ChatOpenAI patched, no model call). Exit `0`. JSON has `source.contradictory_tools_edges: true` (`has_tools_to_llm` and `has_tools_to_end` both true from `librarian.py` text). `compiled_has_tools_to_llm` is true. `compiled_has_tools_to_end` may be false: current `get_graph()` only lists `tools -> tool_calling_llm`.
- **Live run.** The same helper POSTs `Please find The Mom Test at the library` to `/threads/{id}/runs/wait`. Exit `0`. `routing_trace` contains `llm->tools:...`.
- **Proof.** `graph-routing-edges.stdout.txt` and `graph-routing-run.stdout.txt` under `evidence/runs/<id>/`. Record whether the live run also showed a post-tool model message (`llm->end_or_text` after a `tools:` event). Today's observed path is tools back to the LLM, then `tools_condition` to `END` when the model stops calling tools. Do not rewrite the graph to make the trace prettier.

## Gotchas

- `librarian.py` contains both `builder.add_edge("tools", "tool_calling_llm")` and `builder.add_edge("tools", END)`. That contradiction is in-scope to **document**, out of scope to fix.
- Current `graph.get_graph()` only emits `tools -> tool_calling_llm`. The `tools -> END` line is still in source. Live runs follow the loop (another model step after tools) and then end via `tools_condition` on `tool_calling_llm`. Report both the source pair and the compiled/live view. Never delete the extra `add_edge` to make the inspector greener.
- `tools_condition` is the only conditional router, and it sits on `tool_calling_llm`, not on `tools`.
- If no usable model key is available, the scripted LLM still emits `search_library_page` then (if the loop runs) `write_to_notion`. The write hits the Notion mock, not `api.notion.com`.
- Inspecting `graph.get_graph()` in-process is how we pin the edges. It is not a substitute for the live `/runs/wait` drive.
