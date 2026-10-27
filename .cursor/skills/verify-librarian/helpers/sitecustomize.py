"""Process-wide guards for a verify-librarian langgraph dev child.

Loaded automatically when this directory is on PYTHONPATH. It never sends
traffic to api.notion.com. Optional scripted LLM when VERIFY_MOCK_LLM=1.
"""

from __future__ import annotations

import json
import os
from typing import Any

# Dummy Notion values so librarian.py can concatenate headers on import.
# These are not a live integration and must never be sent to Notion.
os.environ.setdefault("NOTION_TOKEN", "secret_VERIFY_NOT_A_REAL_TOKEN")
os.environ.setdefault("NOTION_DATABASE_ID", "verify-not-a-real-database-id")

_GUARD_LOG = os.environ.get("VERIFY_NOTION_GUARD_LOG", "")


def _append_guard_log(event: dict[str, Any]) -> None:
    if not _GUARD_LOG:
        return
    try:
        os.makedirs(os.path.dirname(_GUARD_LOG), exist_ok=True)
        with open(_GUARD_LOG, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, sort_keys=True) + "\n")
    except OSError:
        pass


def _is_notion_url(url: Any) -> bool:
    return "api.notion.com" in str(url)


def _mock_notion_body(url: Any) -> bytes:
    url_s = str(url)
    if "/databases/" in url_s and url_s.rstrip("/").endswith("query"):
        payload = {"object": "list", "results": [], "has_more": False, "next_cursor": None}
    else:
        payload = {"object": "page", "id": "verify-mock-page"}
    return json.dumps(payload).encode("utf-8")


def _install_requests_guard() -> None:
    import requests

    real_request = requests.sessions.Session.request

    def guarded_request(self, method, url, *args, **kwargs):  # type: ignore[no-untyped-def]
        if _is_notion_url(url):
            _append_guard_log(
                {
                    "blocked_live": True,
                    "library": "requests",
                    "method": str(method),
                    "mocked": True,
                    "url": str(url),
                }
            )
            response = requests.models.Response()
            response.status_code = 200
            response._content = _mock_notion_body(url)
            response.headers["Content-Type"] = "application/json"
            response.url = str(url)
            return response
        return real_request(self, method, url, *args, **kwargs)

    requests.sessions.Session.request = guarded_request  # type: ignore[method-assign]


def _install_httpx_guard() -> None:
    try:
        import httpx
    except ImportError:
        return

    real_send = httpx.Client.send

    def guarded_send(self, request, *args, **kwargs):  # type: ignore[no-untyped-def]
        if _is_notion_url(getattr(request, "url", "")):
            _append_guard_log(
                {
                    "blocked_live": True,
                    "library": "httpx",
                    "method": str(getattr(request, "method", "")),
                    "mocked": True,
                    "url": str(request.url),
                }
            )
            return httpx.Response(
                200,
                content=_mock_notion_body(request.url),
                headers={"Content-Type": "application/json"},
                request=request,
            )
        return real_send(self, request, *args, **kwargs)

    httpx.Client.send = guarded_send  # type: ignore[method-assign]


def _install_llm_mock() -> None:
    if os.environ.get("VERIFY_MOCK_LLM") != "1":
        _append_guard_log({"llm_mock": False})
        return

    from langchain_core.messages import AIMessage
    import langchain_openai

    class FakeBoundLLM:
        def invoke(self, messages):  # type: ignore[no-untyped-def]
            last = messages[-1]
            last_name = getattr(last, "name", "") or ""
            last_type = getattr(last, "type", "") or last.__class__.__name__
            human = ""
            for message in messages:
                mtype = getattr(message, "type", "") or message.__class__.__name__
                if mtype in {"human", "HumanMessage"}:
                    human = getattr(message, "content", "") or human
            title = (human or "Atomic Habits").strip()
            lowered = title.lower()
            marker = "looking for"
            if marker in lowered:
                title = title[lowered.index(marker) + len(marker) :].strip(" .\"'")
            if last_type in {"tool", "ToolMessage"}:
                if last_name == "search_library_page":
                    return AIMessage(
                        content="",
                        tool_calls=[
                            {
                                "name": "write_to_notion",
                                "args": {
                                    "book_title": title,
                                    "call_number": "158.1 CLE",
                                    "status": "Available now",
                                    "location": "Sunnyvale Public Library",
                                },
                                "id": "call_write_verify",
                            }
                        ],
                    )
                return AIMessage(content=f"Logged '{title}' to the Book Tracker.")
            return AIMessage(
                content="",
                tool_calls=[
                    {
                        "name": "search_library_page",
                        "args": {"query": title},
                        "id": "call_search_verify",
                    }
                ],
            )

    class FakeChatOpenAI:
        def __init__(self, *args, **kwargs):  # type: ignore[no-untyped-def]
            pass

        def bind_tools(self, tools):  # type: ignore[no-untyped-def]
            return FakeBoundLLM()

    langchain_openai.ChatOpenAI = FakeChatOpenAI  # type: ignore[misc, assignment]
    _append_guard_log({"llm_mock": True})


_install_requests_guard()
_install_httpx_guard()
_install_llm_mock()
_append_guard_log({"guard_installed": True})
