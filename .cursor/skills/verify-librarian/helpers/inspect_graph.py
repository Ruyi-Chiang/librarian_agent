#!/usr/bin/env python3
"""Print compiled librarian graph edges. ChatOpenAI is patched; no model call."""

from __future__ import annotations

import importlib
import json
import os
import sys
from unittest.mock import MagicMock, patch


def main() -> int:
    os.environ.setdefault("NOTION_TOKEN", "secret_VERIFY_NOT_A_REAL_TOKEN")
    os.environ.setdefault("NOTION_DATABASE_ID", "verify-not-a-real-database-id")
    os.environ.setdefault("OPENAI_API_KEY", "sk-verify-not-a-real-key")

    with patch("langchain_openai.ChatOpenAI") as mock_chat:
        mock_chat.return_value.bind_tools.return_value = MagicMock()
        librarian = importlib.import_module("librarian")

    graph = librarian.graph.get_graph()
    edges = []
    for edge in graph.edges:
        source = getattr(edge, "source", None)
        target = getattr(edge, "target", None)
        conditional = bool(getattr(edge, "conditional", False))
        edges.append(
            {
                "source": source,
                "target": target,
                "conditional": conditional,
            }
        )

    tools_targets = sorted({item["target"] for item in edges if item["source"] == "tools"})
    payload = {
        "assistant": "librarian",
        "entry": "./librarian.py:graph",
        "edges": edges,
        "tools_targets": tools_targets,
        "has_tools_to_llm": "tool_calling_llm" in tools_targets,
        "has_tools_to_end": "__end__" in tools_targets or "END" in tools_targets,
    }
    # LangGraph labels the terminal as __end__.
    end_aliases = {"__end__", "END", "__end"}
    payload["has_tools_to_end"] = any(target in end_aliases for target in tools_targets)
    json.dump(payload, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")

    if not payload["has_tools_to_llm"]:
        print("missing tools -> tool_calling_llm edge", file=sys.stderr)
        return 2
    if not payload["has_tools_to_end"]:
        print("missing tools -> END edge (still required: document current contradiction)", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
