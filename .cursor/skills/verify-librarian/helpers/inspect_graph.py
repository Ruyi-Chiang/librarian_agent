#!/usr/bin/env python3
"""Report librarian graph edges from source and from the compiled drawable graph.

ChatOpenAI is patched; this process does not call a model or Notion.
"""

from __future__ import annotations

import importlib
import json
import os
import pathlib
import sys
from unittest.mock import MagicMock, patch

END_ALIASES = {"__end__", "END", "__end"}


def _source_edges(repo_root: pathlib.Path) -> dict:
    text = (repo_root / "librarian.py").read_text(encoding="utf-8")
    has_tools_to_llm = 'builder.add_edge("tools", "tool_calling_llm")' in text
    has_tools_to_end = 'builder.add_edge("tools", END)' in text
    return {
        "has_tools_to_llm": has_tools_to_llm,
        "has_tools_to_end": has_tools_to_end,
        "contradictory_tools_edges": has_tools_to_llm and has_tools_to_end,
    }


def main() -> int:
    os.environ.setdefault("NOTION_TOKEN", "secret_VERIFY_NOT_A_REAL_TOKEN")
    os.environ.setdefault("NOTION_DATABASE_ID", "verify-not-a-real-database-id")
    os.environ.setdefault("OPENAI_API_KEY", "sk-verify-not-a-real-key")

    here = pathlib.Path(__file__).resolve()
    repo_root = next(
        candidate
        for candidate in here.parents
        if (candidate / "librarian.py").is_file() and (candidate / "langgraph.json").is_file()
    )
    source = _source_edges(repo_root)

    with patch("langchain_openai.ChatOpenAI") as mock_chat:
        mock_chat.return_value.bind_tools.return_value = MagicMock()
        if str(repo_root) not in sys.path:
            sys.path.insert(0, str(repo_root))
        librarian = importlib.import_module("librarian")

    graph = librarian.graph.get_graph()
    edges = []
    for edge in graph.edges:
        edges.append(
            {
                "source": getattr(edge, "source", None),
                "target": getattr(edge, "target", None),
                "conditional": bool(getattr(edge, "conditional", False)),
            }
        )

    tools_targets = sorted({item["target"] for item in edges if item["source"] == "tools"})
    payload = {
        "assistant": "librarian",
        "entry": "./librarian.py:graph",
        "edges": edges,
        "tools_targets": tools_targets,
        "has_tools_to_llm": source["has_tools_to_llm"],
        "has_tools_to_end": source["has_tools_to_end"],
        "source": source,
        "compiled_has_tools_to_llm": "tool_calling_llm" in tools_targets,
        "compiled_has_tools_to_end": any(target in END_ALIASES for target in tools_targets),
    }
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")

    if not source["contradictory_tools_edges"]:
        print(
            "source is missing the current tools -> tool_calling_llm and/or tools -> END add_edge",
            file=sys.stderr,
        )
        return 2
    if not payload["compiled_has_tools_to_llm"]:
        print("compiled graph missing tools -> tool_calling_llm", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
