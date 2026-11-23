#!/usr/bin/env bash
# Stop only the langgraph pid this run started. Never delete evidence.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Fail closed: rejected isolation or a marker/run-id mismatch must not
# reach kill or rm -rf. Missing scratch is a no-op.
require_isolated_scratch
if [[ ! -d "${VERIFY_SCRATCH}" ]]; then
  echo "cleanup: no scratch at ${VERIFY_SCRATCH}"
  echo "evidence_kept=${VERIFY_EVIDENCE}"
  exit 0
fi
require_our_scratch

kill_run_langgraph
rm -rf "${VERIFY_SCRATCH}"
echo "cleanup_ok scratch_removed=${VERIFY_SCRATCH}"
echo "evidence_kept=${VERIFY_EVIDENCE}"

if [[ ! -d "${VERIFY_EVIDENCE}" ]]; then
  echo "cleanup: evidence directory missing after cleanup: ${VERIFY_EVIDENCE}" >&2
  exit 2
fi
