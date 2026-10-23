"""notion_database.get_pages is driven only through mocked requests."""

import importlib
import os
from unittest.mock import MagicMock, patch

os.environ["NOTION_TOKEN"] = "secret_TEST123"
os.environ["NOTION_DATABASE_ID"] = "test-database-id"

_IMPORT_PAGE = {"id": "page-import", "object": "page"}


def _query_response(results, has_more=False, next_cursor=None):
    resp = MagicMock()
    resp.status_code = 200
    resp.json.return_value = {
        "object": "list",
        "results": results,
        "has_more": has_more,
        "next_cursor": next_cursor,
    }
    return resp


# Module body calls print(get_pages()) — mock before import so nothing goes live.
with patch("requests.post", return_value=_query_response([_IMPORT_PAGE])):
    notion_database = importlib.import_module("notion_database")


def test_get_pages_follows_cursor_when_num_pages_is_none():
    page_a = {"id": "page-a"}
    page_b = {"id": "page-b"}
    first = _query_response([page_a], has_more=True, next_cursor="cursor-1")
    second = _query_response([page_b], has_more=False)

    with patch("notion_database.requests.post", side_effect=[first, second]) as mock_post:
        results = notion_database.get_pages()

    assert results == [page_a, page_b]
    assert mock_post.call_count == 2
    first_url = mock_post.call_args_list[0].args[0]
    second_url = mock_post.call_args_list[1].args[0]
    assert first_url.endswith("/v1/databases/test-database-id/query")
    assert second_url.endswith("/v1/databases/test-database-id/query")
    assert mock_post.call_args_list[0].kwargs["json"]["page_size"] == 100
    assert mock_post.call_args_list[1].kwargs["json"]["start_cursor"] == "cursor-1"


def test_get_pages_finite_num_pages_is_page_size_and_does_not_loop():
    page = {"id": "page-only"}
    response = _query_response([page], has_more=True, next_cursor="ignored")

    with patch("notion_database.requests.post", return_value=response) as mock_post:
        results = notion_database.get_pages(num_pages=5)

    assert results == [page]
    assert mock_post.call_count == 1
    assert mock_post.call_args.kwargs["json"] == {"page_size": 5}
    assert mock_post.call_args.args[0].endswith("/v1/databases/test-database-id/query")
