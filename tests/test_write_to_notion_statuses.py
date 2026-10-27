"""write_to_notion must post each allowed status through a mocked requests layer."""

import importlib
import os
from unittest.mock import MagicMock, patch

os.environ["NOTION_TOKEN"] = "secret_TEST123"
os.environ["NOTION_DATABASE_ID"] = "test-database-id"
os.environ.setdefault("OPENAI_API_KEY", "sk-test-not-a-real-key")

with patch("langchain_openai.ChatOpenAI") as mock_chat:
    mock_chat.return_value.bind_tools.return_value = MagicMock()
    librarian = importlib.import_module("librarian")

STATUSES = (
    "Available now",
    "Not available",
    "Not Available",
    "All copies in use",
)


def _write():
    return getattr(librarian.write_to_notion, "func", librarian.write_to_notion)


def test_write_to_notion_posts_each_status():
    fake_response = MagicMock()
    fake_response.status_code = 200
    fake_response.text = '{"id": "page-test"}'
    write = _write()

    for status in STATUSES:
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
