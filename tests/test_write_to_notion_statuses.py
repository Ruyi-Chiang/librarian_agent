"""write_to_notion must post each allowed status through a mocked requests layer."""

import importlib
import os
from typing import Literal, get_args, get_origin, get_type_hints
from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

os.environ["NOTION_TOKEN"] = "secret_TEST123"
os.environ["NOTION_DATABASE_ID"] = "test-database-id"
os.environ.setdefault("OPENAI_API_KEY", "sk-test-not-a-real-key")

with patch("langchain_openai.ChatOpenAI") as mock_chat:
    mock_chat.return_value.bind_tools.return_value = MagicMock()
    librarian = importlib.import_module("librarian")

STATUSES = librarian.BOOK_STATUSES
INVALID_STATUSES = (
    "Checked out",
    "Not Available",
    "available now",
    "",
)


def _write():
    return getattr(librarian.write_to_notion, "func", librarian.write_to_notion)


def test_write_to_notion_status_is_literal_not_str():
    hints = get_type_hints(librarian.write_to_notion.func)
    resolved = hints["status"]
    assert get_origin(resolved) is Literal
    assert resolved is not str
    assert get_args(resolved) == STATUSES
    assert get_args(resolved) == (
        "Available now",
        "Not available",
        "All copies in use",
    )


def test_system_prompt_allowed_statuses_match_literal():
    expected = ", ".join(f'"{s}"' for s in STATUSES)
    assert f"Allowed book statuses: {expected}." in librarian.LIBRARIAN_SYSTEM_PROMPT
    docstring = librarian.write_to_notion.func.__doc__
    for status in STATUSES:
        assert f'"{status}"' in docstring
    assert "Not Available" not in librarian.LIBRARIAN_SYSTEM_PROMPT
    assert "Not Available" not in docstring


@pytest.mark.parametrize("status", STATUSES)
def test_write_to_notion_posts_each_status(status):
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.text = '{"id": "page-test"}'
    write = _write()

    with patch("librarian.requests.post", return_value=fake_response) as mock_post:
        message = write(
            book_title="Status Probe",
            call_number="000 VER",
            status=status,
            date_str="verify-day",
        )

    assert mock_post.call_count == 1
    url = mock_post.call_args.args[0]
    assert url.endswith("/v1/pages")
    assert "api.notion.com" in url
    payload = mock_post.call_args.kwargs["json"]
    assert payload["parent"]["database_id"] == "test-database-id"
    assert payload["properties"]["Status"]["status"]["name"] == status
    assert "Successfully added 'Status Probe' to Notion database" in message
    assert status in message


@pytest.mark.parametrize("status", INVALID_STATUSES)
def test_write_to_notion_rejects_invalid_status(status):
    write = _write()
    with patch("librarian.requests.post") as mock_post:
        message = write(
            book_title="Status Probe",
            call_number="000 VER",
            status=status,
            date_str="verify-day",
        )

    assert mock_post.call_count == 0
    assert "invalid status" in message.lower()


@pytest.mark.parametrize("status", INVALID_STATUSES)
def test_write_to_notion_schema_rejects_invalid_status(status):
    schema = librarian.write_to_notion.args_schema
    with pytest.raises(ValidationError):
        schema(book_title="Status Probe", call_number="000 VER", status=status)
