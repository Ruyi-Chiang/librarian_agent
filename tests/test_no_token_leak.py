"""Regression: Notion write path must not print or log the integration token."""

import importlib
import logging
import os
from unittest.mock import MagicMock, patch

# librarian.py reads env vars at import time.
os.environ["NOTION_TOKEN"] = "secret_TEST123"
os.environ["NOTION_DATABASE_ID"] = "test-database-id"
os.environ["OPENAI_API_KEY"] = "sk-test-not-a-real-key"

# Avoid constructing a real OpenAI client (and any network) on import.
with patch("langchain_openai.ChatOpenAI") as mock_chat:
    mock_chat.return_value.bind_tools.return_value = MagicMock()
    librarian = importlib.import_module("librarian")

FAKE_TOKEN = "secret_TEST123"


def test_create_notion_page_and_write_to_notion_do_not_leak_token(capsys, caplog):
    caplog.set_level(logging.DEBUG)
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.text = '{"id": "page-test"}'

    with patch("librarian.requests.post", return_value=fake_response) as mock_post:
        result = librarian.create_notion_page(
            {"Title": {"title": [{"text": {"content": "Test"}}]}}
        )
        write = getattr(librarian.write_to_notion, "func", librarian.write_to_notion)
        message = write(
            book_title="Test Book",
            call_number="123.45 ABC",
            status="Available now",
        )

    captured = capsys.readouterr()
    leaked = captured.out + captured.err + caplog.text

    assert FAKE_TOKEN not in leaked
    assert "Bearer" not in leaked
    assert result is fake_response
    assert result.status_code == 200
    assert "Successfully added 'Test Book' to Notion database" in message
    assert mock_post.call_count == 2
