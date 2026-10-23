#!/usr/bin/env python3
"""Drive one librarian run on a local langgraph dev server. Never calls Notion."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request


def _request(method: str, url: str, payload: dict | None = None, timeout: float = 180.0) -> dict:
    data = None
    headers = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            if not body:
                return {"status_code": resp.status}
            return json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {exc.code} {url}: {detail}") from exc


def _message_type(message: dict) -> str:
    return str(message.get("type") or message.get("role") or "")


def _tool_names(message: dict) -> list[str]:
    names: list[str] = []
    for call in message.get("tool_calls") or []:
        if isinstance(call, dict):
            name = call.get("name") or call.get("function", {}).get("name")
            if name:
                names.append(str(name))
    additional = message.get("additional_kwargs") or {}
    for call in additional.get("tool_calls") or []:
        if isinstance(call, dict):
            name = call.get("function", {}).get("name") or call.get("name")
            if name:
                names.append(str(name))
    if message.get("name"):
        names.append(str(message["name"]))
    return names


def _routing_trace(messages: list[dict]) -> list[str]:
    trace: list[str] = []
    for message in messages:
        kind = _message_type(message)
        names = _tool_names(message)
        if kind in {"ai", "AIMessage"} and any(names):
            trace.append("llm->tools:" + ",".join(names))
        elif kind in {"tool", "ToolMessage"}:
            label = names[0] if names else "unknown"
            trace.append("tools:" + label)
        elif kind in {"ai", "AIMessage"}:
            trace.append("llm->end_or_text")
        elif kind in {"human", "HumanMessage"}:
            trace.append("user")
    return trace


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--message", default="I am looking for Atomic Habits")
    parser.add_argument("--assistant-id", default="librarian")
    parser.add_argument("--out", help="Write the raw wait payload here")
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    if "api.notion.com" in base:
        print("refuse: base URL must be the local langgraph server, not Notion", file=sys.stderr)
        return 2

    thread = _request("POST", f"{base}/threads", {})
    thread_id = thread.get("thread_id")
    if not thread_id:
        print(json.dumps({"error": "no thread_id", "body": thread}, indent=2))
        return 2

    result = _request(
        "POST",
        f"{base}/threads/{thread_id}/runs/wait",
        {
            "assistant_id": args.assistant_id,
            "input": {"messages": [{"role": "human", "content": args.message}]},
        },
    )

    messages = result.get("messages") or []
    if not messages and isinstance(result.get("values"), dict):
        messages = result["values"].get("messages") or []

    summary = {
        "assistant_id": args.assistant_id,
        "base_url": base,
        "guard_log": os.environ.get("VERIFY_NOTION_GUARD_LOG"),
        "llm_mock": os.environ.get("VERIFY_MOCK_LLM") == "1",
        "message": args.message,
        "routing_trace": _routing_trace(messages if isinstance(messages, list) else []),
        "thread_id": thread_id,
        "tool_names": [],
    }
    if isinstance(messages, list):
        for message in messages:
            summary["tool_names"].extend(_tool_names(message))
    # unique preserve order
    seen: set[str] = set()
    unique = []
    for name in summary["tool_names"]:
        if name not in seen:
            seen.add(name)
            unique.append(name)
    summary["tool_names"] = unique

    if args.out:
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=2, default=str)
            handle.write("\n")

    json.dump(summary, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")

    if "user" not in summary["routing_trace"]:
        print("expected a human message in the run", file=sys.stderr)
        return 2
    if not any(item.startswith("llm->tools") for item in summary["routing_trace"]):
        print("expected LLM to route to tools", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
