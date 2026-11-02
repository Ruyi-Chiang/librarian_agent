#!/usr/bin/env bash
# Drive one mapped verify-librarian feature (or `all`).

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<'EOF'
Usage: helpers/drive.sh <feature>|all

Features:
  parse-book-request   live langgraph (Notion mocked)
  graph-routing        live langgraph (Notion mocked)
  write-to-notion      pytest, requests mocked
  get-pages            pytest, requests mocked
  no-token-leak        pytest, requests mocked
  all                  every mapped feature once
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

FEATURE="$1"
require_our_scratch
cd "${REPO_ROOT}"

# Re-export launch env so Notion stays dummy even if the parent shell had real values.
if [[ -f "${VERIFY_SCRATCH}/launch.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  . "${VERIFY_SCRATCH}/launch.env"
  set +a
fi
export NOTION_TOKEN="secret_VERIFY_NOT_A_REAL_TOKEN"
export NOTION_DATABASE_ID="verify-not-a-real-database-id"
export VERIFY_NOTION_GUARD_LOG="${VERIFY_NOTION_GUARD_LOG:-${VERIFY_SCRATCH}/notion-guard.jsonl}"
# sitecustomize stays in the langgraph child (launch set its PYTHONPATH).
# Pytest uses tests/conftest.py; do not load the live guard into pytest.

drive_parse() {
  local base out
  base="$(langgraph_url)"
  out="${VERIFY_EVIDENCE}/parse-book-request.wait.json"
  capture parse-book-request \
    "${PY}" "${SKILL_DIR}/helpers/drive_langgraph.py" \
    --base-url "${base}" \
    --message "I am looking for Atomic Habits" \
    --out "${out}"
  if grep -q 'search_library_page' "${VERIFY_EVIDENCE}/parse-book-request.stdout.txt"; then
    append_summary parse-book-request ok "langgraph catalog search invoked"
  else
    append_summary parse-book-request fail "search_library_page missing from routing"
    return 2
  fi
}

drive_graph() {
  local base
  base="$(langgraph_url)"
  capture graph-routing-edges \
    env PYTHONPATH="${REPO_ROOT}" \
    "${PY}" "${SKILL_DIR}/helpers/inspect_graph.py"
  capture graph-routing-run \
    "${PY}" "${SKILL_DIR}/helpers/drive_langgraph.py" \
    --base-url "${base}" \
    --message "Please find The Mom Test at the library" \
    --out "${VERIFY_EVIDENCE}/graph-routing.wait.json"
  if grep -q 'has_tools_to_end.: true' "${VERIFY_EVIDENCE}/graph-routing-edges.stdout.txt"; then
    append_summary graph-routing fail "tools -> END edge still present"
    return 2
  fi
  if ! grep -q 'has_tools_to_llm.: true' "${VERIFY_EVIDENCE}/graph-routing-edges.stdout.txt"; then
    append_summary graph-routing fail "compiled graph missing tools -> tool_calling_llm"
    return 2
  fi
  if ! grep -q 'llm->tools' "${VERIFY_EVIDENCE}/graph-routing-run.stdout.txt"; then
    append_summary graph-routing fail "live run did not route LLM to tools"
    return 2
  fi
  append_summary graph-routing ok "edges plus live LLM-to-tools run"
}

drive_pytest() {
  local name="$1"
  local nodeid="$2"
  capture "${name}" \
    "${PY}" -m pytest -q --basetemp="${VERIFY_SCRATCH}/pytest-${name}" "${nodeid}"
  append_summary "${name}" ok "pytest ${nodeid}"
}

drive_one() {
  case "$1" in
    parse-book-request) drive_parse ;;
    graph-routing) drive_graph ;;
    write-to-notion) drive_pytest write-to-notion tests/test_write_to_notion_statuses.py ;;
    get-pages) drive_pytest get-pages tests/test_get_pages.py ;;
    no-token-leak) drive_pytest no-token-leak tests/test_no_token_leak.py ;;
    all)
      drive_parse
      drive_graph
      drive_pytest write-to-notion tests/test_write_to_notion_statuses.py
      drive_pytest get-pages tests/test_get_pages.py
      drive_pytest no-token-leak tests/test_no_token_leak.py
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "unknown feature: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
}

drive_one "${FEATURE}"
echo "drive_ok feature=${FEATURE} evidence=${VERIFY_EVIDENCE}"
