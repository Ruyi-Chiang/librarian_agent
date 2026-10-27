"""Session-wide fence: pytest must never open a socket to api.notion.com."""

from __future__ import annotations

import requests

_REAL_REQUEST = requests.sessions.Session.request


def _block_live_notion(self, method, url, *args, **kwargs):  # type: ignore[no-untyped-def]
    if "api.notion.com" in str(url):
        raise AssertionError(
            f"blocked live Notion call: {method} {url}. "
            "Patch requests at the product boundary instead."
        )
    return _REAL_REQUEST(self, method, url, *args, **kwargs)


def pytest_configure(config):  # type: ignore[no-untyped-def]
    requests.sessions.Session.request = _block_live_notion  # type: ignore[method-assign]


def pytest_unconfigure(config):  # type: ignore[no-untyped-def]
    requests.sessions.Session.request = _REAL_REQUEST  # type: ignore[method-assign]
