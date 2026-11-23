#!/usr/bin/env bash
# Prove the mkdir-lock fallback is released when the protected claim fails.
# Isolated cache/lock paths; does not touch repo-root .langgraph_api.

set -euo pipefail
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

work="/tmp/verify-librarian-lock-release-$$"
rm -rf "${work}"
mkdir -p "${work}"
export VERIFY_LGAPI_DIR="${work}/not-a-dir"
export VERIFY_LGAPI_LOCK="${work}/verify-librarian-lgapi.lock"
export VERIFY_LGAPI_FORCE_MKDIR_LOCK=1
: > "${VERIFY_LGAPI_DIR}"

. "${_THIS_DIR}/common.sh"

repo_cache="${REPO_ROOT}/.langgraph_api"
if [[ "${LANGGRAPH_API_DIR}" == "${repo_cache}" ]]; then
  echo "refuse: lock-release check must not use repo-root ${repo_cache}" >&2
  rm -rf "${work}"
  exit 2
fi

status=0
claim_langgraph_api_dir && status=0 || status=$?
if [[ "${status}" -eq 0 ]]; then
  echo "FAIL: expected claim to refuse a non-directory cache" >&2
  rm -rf "${work}"
  exit 2
fi
if [[ -e "${LANGGRAPH_API_LOCK}.d" ]]; then
  echo "FAIL: mkdir lock left behind at ${LANGGRAPH_API_LOCK}.d" >&2
  rm -rf "${work}"
  exit 2
fi
rm -rf "${work}"
echo "PASS: mkdir lock released after claim refuse"
