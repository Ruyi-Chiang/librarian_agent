#!/usr/bin/env bash
# Install the verify venv, open isolated scratch, start langgraph dev with Notion mocked.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

prepare_scratch
cd "${REPO_ROOT}"

if [[ ! -x "${PY}" ]]; then
  rm -rf "${VERIFY_VENV}"
  python3 -m venv "${VERIFY_VENV}"
elif ! "${PY}" -c 'import pip' >/dev/null 2>&1; then
  rm -rf "${VERIFY_VENV}"
  python3 -m venv "${VERIFY_VENV}"
fi
"${PY}" -m pip install --upgrade pip >/dev/null
"${PY}" -m pip install -r "${SKILL_DIR}/helpers/requirements.txt"

# Never inherit a real Notion integration into the child. Dummy values plus the
# sitecustomize guard mean api.notion.com is not contacted.
export NOTION_TOKEN="secret_VERIFY_NOT_A_REAL_TOKEN"
export NOTION_DATABASE_ID="verify-not-a-real-database-id"
export LANGCHAIN_TRACING_V2="${LANGCHAIN_TRACING_V2:-false}"
export LANGSMITH_TRACING="${LANGSMITH_TRACING:-false}"

if [[ -z "${OPENAI_API_KEY:-}" || "${OPENAI_API_KEY}" == sk-test* || "${OPENAI_API_KEY}" == sk-verify* ]]; then
  export VERIFY_MOCK_LLM=1
  export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-verify-not-a-real-key}"
fi

export VERIFY_NOTION_GUARD_LOG="${VERIFY_SCRATCH}/notion-guard.jsonl"
export PYTHONPATH="${SKILL_DIR}/helpers${PYTHONPATH:+:${PYTHONPATH}}"

if [[ -z "${VERIFY_LANGGRAPH_PORT:-}" ]]; then
  VERIFY_LANGGRAPH_PORT="$("${PY}" -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
fi
export VERIFY_LANGGRAPH_PORT
printf '%s\n' "${VERIFY_LANGGRAPH_PORT}" > "${VERIFY_SCRATCH}/langgraph.port"

{
  echo "VERIFY_RUN_ID=${VERIFY_RUN_ID}"
  echo "VERIFY_SCRATCH=${VERIFY_SCRATCH}"
  echo "VERIFY_EVIDENCE=${VERIFY_EVIDENCE}"
  echo "VERIFY_LANGGRAPH_PORT=${VERIFY_LANGGRAPH_PORT}"
  echo "VERIFY_MOCK_LLM=${VERIFY_MOCK_LLM:-0}"
  echo "VERIFY_NOTION_GUARD_LOG=${VERIFY_NOTION_GUARD_LOG}"
} > "${VERIFY_SCRATCH}/launch.env"

if [[ -f "${VERIFY_SCRATCH}/langgraph.pid" ]]; then
  old_pid="$(tr -d '[:space:]' < "${VERIFY_SCRATCH}/langgraph.pid")"
  if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
    echo "launch_ok reused_pid=${old_pid} url=$(langgraph_url)"
    exit 0
  fi
fi

: > "${VERIFY_SCRATCH}/langgraph.stdout.log"
: > "${VERIFY_SCRATCH}/langgraph.stderr.log"

"${LANGGRAPH_BIN}" dev \
  --no-browser \
  --host 127.0.0.1 \
  --port "${VERIFY_LANGGRAPH_PORT}" \
  >"${VERIFY_SCRATCH}/langgraph.stdout.log" \
  2>"${VERIFY_SCRATCH}/langgraph.stderr.log" &
echo $! > "${VERIFY_SCRATCH}/langgraph.pid"
lg_pid="$(tr -d '[:space:]' < "${VERIFY_SCRATCH}/langgraph.pid")"

ready=0
for _ in $(seq 1 90); do
  if ! kill -0 "${lg_pid}" 2>/dev/null; then
    echo "langgraph dev exited before ready; see ${VERIFY_SCRATCH}/langgraph.stderr.log" >&2
    tail -n 80 "${VERIFY_SCRATCH}/langgraph.stderr.log" >&2 || true
    exit 2
  fi
  if "${PY}" -c 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=2).read()' "$(langgraph_url)/ok" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [[ "${ready}" != "1" ]]; then
  echo "langgraph /ok never became ready on $(langgraph_url)" >&2
  tail -n 80 "${VERIFY_SCRATCH}/langgraph.stderr.log" >&2 || true
  exit 2
fi

echo "launch_ok pid=${lg_pid} url=$(langgraph_url) mock_llm=${VERIFY_MOCK_LLM:-0} scratch=${VERIFY_SCRATCH}"
