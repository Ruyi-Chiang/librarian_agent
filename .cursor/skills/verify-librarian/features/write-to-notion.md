# Write to Notion

`write_to_notion` (a LangChain tool on `librarian.py`) builds a Book Tracker page payload and POSTs it through `create_notion_page`. Allowed status names in the tool docstring are `Available now`, `Not Available`, and `All copies in use`. The system prompt also says `Not available`. This feature drives **each** of those strings through pytest with `requests` mocked.

## Sub-features

- `status-available-now` writes `Status.status.name = Available now`.
- `status-not-available` writes `Not available` (prompt spelling).
- `status-not-available-capital` writes `Not Available` (docstring spelling).
- `status-all-copies-in-use` writes `All copies in use`.
- `create-wrapper` is `create_notion_page` posting to the pages endpoint with the dummy parent database id.

## How to get to it (user POV)

- In Studio, after a catalog hit, the assistant is supposed to record the book with one of the allowed statuses.
- The user sees a confirmation string (`Successfully added ...` or a failure status code).
- There is no dedicated test database today, so a user-visible live write would land on Ruyi's real board. Verification must not do that.

## Driving it with pytest

Preconditions:

- `.venv` from `helpers/launch.sh` (or any environment with pytest + the product imports).
- `tests/conftest.py` blocks leftover live Notion HTTP at `Session.request`.
- Each test patches `librarian.requests.post`.

- **Default verification (harness).** Run `helpers/drive.sh write-to-notion`. That runs `tests/test_write_to_notion_statuses.py`. Exit code `0`.
- **Proof.** Pytest transcript under `evidence/runs/<id>/write-to-notion.stdout.txt`. Each status test asserts the mocked POST URL contains the pages path, the payload `Status` name equals the string under test, and no real socket to Notion was used.
- **Not allowed.** A live Studio click that creates a row in Ruyi's Book Tracker. No dedicated test database exists.

## Gotchas

- HARD RULE: never call `api.notion.com` and never write to Ruyi's real Notion. A live write is allowed only against a dedicated test database she provides; none exists today.
- Prompt and docstring disagree on `Not available` vs `Not Available`. Drive both. Do not collapse them into one case.
- `librarian.py` concatenates `NOTION_TOKEN` at import. Tests must set a dummy token before import.
- `write_to_notion` is a `@tool`; call `write_to_notion.func` (or the attribute the existing leak test uses) so the test invokes the raw function.
- Success is `response.status_code == 200` from the mock, not a page id appearing in Notion.
