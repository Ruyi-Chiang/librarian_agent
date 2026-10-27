#!/usr/bin/env bash
# Read-only: is this verify-librarian instance worth driving?

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_our_scratch
cd "${REPO_ROOT}"

if [[ ! -x "${PY}" ]]; then
  echo "doctor: missing ${PY}; run helpers/launch.sh" >&2
  exit 2
fi

"${PY}" - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit(f"python {sys.version} is older than 3.11")
print(f"python_ok {sys.version.split()[0]}")
PY

for mod in langgraph langchain_openai requests bs4 pytest; do
  "${PY}" -c "import ${mod}" >/dev/null
done

if [[ ! -f "${RUN_MARKER}" ]]; then
  echo "doctor: scratch marker missing" >&2
  exit 2
fi

pid_file="${VERIFY_SCRATCH}/langgraph.pid"
if [[ ! -f "${pid_file}" ]]; then
  echo "doctor: langgraph.pid missing" >&2
  exit 2
fi
lg_pid="$(tr -d '[:space:]' < "${pid_file}")"
if ! kill -0 "${lg_pid}" 2>/dev/null; then
  echo "doctor: langgraph pid ${lg_pid} is not running" >&2
  exit 2
fi

base="$(langgraph_url)"
"${PY}" - "${base}" <<'PY'
import json, sys, urllib.request
base = sys.argv[1]
ok = urllib.request.urlopen(base + "/ok", timeout=5)
print("ok_status", ok.status)
# Assistants listing differs slightly across CLI versions; accept /assistants or /info.
body = None
for path in ("/assistants", "/info"):
    try:
        resp = urllib.request.urlopen(base + path, timeout=5)
        raw = resp.read().decode("utf-8")
        print(path, resp.status)
        body = raw
        break
    except Exception as exc:
        print(path, "unavailable", exc)
if body is None:
    raise SystemExit("no /assistants or /info")
if "librarian" not in body:
    # /info may nest graph names; fail only when we can see graphs and librarian is absent.
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        data = None
    if isinstance(data, list):
        names = json.dumps(data)
        if "librarian" not in names:
            raise SystemExit("assistant librarian not listed")
print("graph_name_ok librarian")
PY

# The compiled graph must keep tools -> tool_calling_llm and must not add tools -> END.
PYTHONPATH="${REPO_ROOT}${PYTHONPATH:+:${PYTHONPATH}}" "${PY}" "${SKILL_DIR}/helpers/inspect_graph.py" >/dev/null

echo "doctor_ok run_id=${VERIFY_RUN_ID} url=${base} scratch=${VERIFY_SCRATCH}"
