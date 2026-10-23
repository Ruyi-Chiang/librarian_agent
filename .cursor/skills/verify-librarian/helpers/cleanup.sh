#!/usr/bin/env bash
# Stop only the langgraph pid this run started. Never delete evidence.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_isolated_scratch || true
if [[ ! -d "${VERIFY_SCRATCH}" ]]; then
  echo "cleanup: no scratch at ${VERIFY_SCRATCH}"
  echo "evidence_kept=${VERIFY_EVIDENCE}"
  exit 0
fi

if [[ ! -f "${RUN_MARKER}" ]]; then
  echo "cleanup: refusing to delete VERIFY_SCRATCH=${VERIFY_SCRATCH} (no run marker)" >&2
  echo "evidence_kept=${VERIFY_EVIDENCE}"
  exit 2
fi

pid_file="${VERIFY_SCRATCH}/langgraph.pid"
if [[ -f "${pid_file}" ]]; then
  lg_pid="$(tr -d '[:space:]' < "${pid_file}")"
  if [[ -n "${lg_pid}" ]] && kill -0 "${lg_pid}" 2>/dev/null; then
    kill "${lg_pid}" 2>/dev/null || true
    for _ in $(seq 1 20); do
      if ! kill -0 "${lg_pid}" 2>/dev/null; then
        break
      fi
      sleep 0.2
    done
    if kill -0 "${lg_pid}" 2>/dev/null; then
      kill -9 "${lg_pid}" 2>/dev/null || true
    fi
  fi
fi

rm -rf "${VERIFY_SCRATCH}"
echo "cleanup_ok scratch_removed=${VERIFY_SCRATCH}"
echo "evidence_kept=${VERIFY_EVIDENCE}"

if [[ ! -d "${VERIFY_EVIDENCE}" ]]; then
  echo "cleanup: evidence directory missing after cleanup: ${VERIFY_EVIDENCE}" >&2
  exit 2
fi
