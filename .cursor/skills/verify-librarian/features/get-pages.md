# Query Notion pages

`notion_database.get_pages` POSTs a database query and follows `has_more` / `next_cursor` when `num_pages is None`. When `num_pages` is set, that value is the `page_size` and the function does not loop. This is not a user-facing Studio click; it is the query helper sitting next to the write path.

## Sub-features

- `query-all` (`num_pages is None`) uses `page_size=100` and keeps requesting while `has_more` is true.
- `query-page-size` (finite `num_pages`) sends one request with that `page_size` and returns that page of `results`.
- `import-side-effect` — the module body calls `print(get_pages())` on import.

## How to get to it (user POV)

- A developer (or notebook) imports `notion_database` or calls `get_pages()` to list Book Tracker rows.
- Importing the module immediately queries Notion and prints the result. That is the current product behavior.
- There is no Studio button for this helper.

## Driving it with pytest

Preconditions:

- Patch `requests.post` **before** `import notion_database`. The import-time `print(get_pages())` would otherwise be a live Notion call (forbidden).
- `tests/conftest.py` is a second fence: any un-mocked `api.notion.com` URL raises.

- **Default verification (harness).** Run `helpers/drive.sh get-pages`. That runs `tests/test_get_pages.py`. Exit code `0`.
- **Proof.** The tests assert (1) a paginated `get_pages()` concatenates two mocked result lists, (2) `get_pages(num_pages=5)` sends `page_size=5` once, and (3) every POST URL is the databases-query path on the mock, not a live socket.
- **Not allowed.** `python notion_database.py` against Ruyi's credentials.

## Gotchas

- HARD RULE: never call `api.notion.com`. The module-level `print(get_pages())` makes a naive import a live write/query. Always mock first.
- `num_pages` is **not** "max pages". It is the request `page_size`, and it disables the `has_more` loop.
- `DATABASE_ID` is read at import from `NOTION_DATABASE_ID`. Tests set a dummy id.
- If `NOTION_TOKEN` is unset, `"Bearer " + NOTION_TOKEN` raises before any request. Set a dummy token even though it must never leave the process.
- Do not "prove" this feature by opening the real Book Tracker database in a browser.
