# No token leak

`create_notion_page` and `write_to_notion` must not print or log the Notion integration token (or the `Bearer` header). This is the regression from the token-leak fix. The check is `tests/test_no_token_leak.py`.

## Sub-features

- `create-no-leak` calls `create_notion_page` with a fake token and asserts stdout/stderr/logs omit that token and `Bearer`.
- `write-no-leak` calls `write_to_notion` for a successful mocked write and asserts the same, plus the success message.

## How to get to it (user POV)

- Any Studio or script path that writes a book to Notion goes through `create_notion_page`.
- The user should never see the integration token in the terminal, `langgraph dev` logs, or server logs.
- Developers re-run the pytest file after touching the write path.

## Driving it with pytest

Preconditions:

- Dummy `NOTION_TOKEN=secret_TEST123` is set before `import librarian`.
- `langchain_openai.ChatOpenAI` is patched for import.
- `librarian.requests.post` is mocked; no live Notion.

- **Default verification (harness).** Run `helpers/drive.sh no-token-leak`. That runs `tests/test_no_token_leak.py`. Exit code `0`.
- **Manual equivalent.** `python -m pytest tests/test_no_token_leak.py`.
- **Proof.** Transcript under `evidence/runs/<id>/no-token-leak.stdout.txt`. The test asserts the fake token and `Bearer` are absent from capsys + caplog, the mocked response is returned, and the write success string is present.

## Gotchas

- The fake token in the test is `secret_TEST123`. Do not replace it with a real integration token "to make it more realistic".
- Patch `librarian.requests.post`, not a live session. `tests/conftest.py` will fail the run if anything still aims at `api.notion.com` without a mock.
- Importing `librarian` constructs `ChatOpenAI`. Keep the existing import-time patch so collection does not open a model client.
- This feature does not prove a write to a real database. It proves the write path is quiet.
