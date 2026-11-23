#!/usr/bin/env bash
# Deterministic create-before-mark race check against an isolated cache.
# Never touches repo-root .langgraph_api (developer Studio cache / live runs).
# Default: lock held, B blocks then registers, A's cleanup leaves B's files.
# --bypass-lock: same sequence without the lock; must FAIL (B sees unmarked
# cache, A's cleanup deletes B's files). That proves the test can catch the race.

set -euo pipefail
_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bypass=0
if [[ "${1:-}" == "--bypass-lock" ]]; then
  bypass=1
  export VERIFY_LGAPI_SKIP_LOCK=1
fi

work="/tmp/verify-librarian-race-$$"
rm -rf "${work}"
mkdir -p "${work}"
export VERIFY_LGAPI_DIR="${work}/.langgraph_api"
export VERIFY_LGAPI_LOCK="${work}/verify-librarian-lgapi.lock"

. "${_THIS_DIR}/common.sh"

repo_cache="${REPO_ROOT}/.langgraph_api"
if [[ "${LANGGRAPH_API_DIR}" == "${repo_cache}" ]]; then
  echo "refuse: race check must not use repo-root ${repo_cache}" >&2
  rm -rf "${work}"
  exit 2
fi

a_out="${work}/a.out"
b_out="${work}/b.out"

claim_as() {
  local id="$1"
  local pause="${2:-}"
  (
    export VERIFY_RUN_ID="${id}"
    export VERIFY_LGAPI_DIR VERIFY_LGAPI_LOCK
    if [[ -n "${pause}" ]]; then
      export VERIFY_LGAPI_CLAIM_PAUSE="${pause}"
    else
      unset VERIFY_LGAPI_CLAIM_PAUSE
    fi
    . "${_THIS_DIR}/common.sh"
    claim_langgraph_api_dir
  )
}

cleanup_as() {
  local id="$1"
  (
    export VERIFY_RUN_ID="${id}"
    export VERIFY_LGAPI_DIR VERIFY_LGAPI_LOCK
    unset VERIFY_LGAPI_CLAIM_PAUSE
    . "${_THIS_DIR}/common.sh"
    remove_owned_langgraph_api_dir
  )
}

fail() {
  echo "FAIL: $*" >&2
  echo "--- A ---"; cat "${a_out}" || true
  echo "--- B ---"; cat "${b_out}" || true
  kill "${a_pid:-}" "${b_pid:-}" 2>/dev/null || true
  wait "${a_pid:-}" "${b_pid:-}" 2>/dev/null || true
  rm -rf "${work}"
  exit 2
}

: > "${a_out}"
: > "${b_out}"

echo "mode=$([ "${bypass}" = 1 ] && echo bypass-lock || echo locked) pause=2 isolated=${LANGGRAPH_API_DIR}"
claim_as race-a 2 >"${a_out}" 2>&1 &
a_pid=$!

for _ in $(seq 1 40); do
  if grep -q 'langgraph_api_claim_pause' "${a_out}"; then
    break
  fi
  sleep 0.05
done
if ! grep -q 'langgraph_api_claim_pause' "${a_out}"; then
  fail "A never entered VERIFY_LGAPI_CLAIM_PAUSE"
fi
if [[ -f "${LANGGRAPH_API_OWNED_MARKER}" ]]; then
  fail "marker already present while A is paused"
fi
if [[ ! -d "${LANGGRAPH_API_DIR}" ]]; then
  fail "cache dir missing while A is paused"
fi
echo "pause_window dir_present=1 marker_present=0"

claim_as race-b >"${b_out}" 2>&1 &
b_pid=$!
sleep 0.4

if [[ "${bypass}" == "1" ]]; then
  if kill -0 "${b_pid}" 2>/dev/null; then
    fail "B still running with lock bypassed; negative control did not observe the race"
  fi
  wait "${b_pid}" || true
  wait "${a_pid}" || true
  echo "--- A ---"; cat "${a_out}"
  echo "--- B ---"; cat "${b_out}"
  if ! grep -q 'langgraph_api_unmarked' "${b_out}"; then
    fail "expected B to treat the paused create as unmarked"
  fi
  printf 'sentinel-b\n' > "${LANGGRAPH_API_DIR}/SENTINEL-B.txt"
  cleanup_as race-a
  if [[ -e "${LANGGRAPH_API_DIR}/SENTINEL-B.txt" ]]; then
    fail "expected A's cleanup to delete B's files when B never registered"
  fi
  rm -rf "${work}"
  echo "FAIL: lock bypassed; B unmarked; A's cleanup deleted B's files"
  exit 2
fi

if grep -q 'langgraph_api_unmarked' "${b_out}"; then
  fail "B treated A's paused create as an unmarked developer cache"
fi
if ! kill -0 "${b_pid}" 2>/dev/null; then
  fail "B finished while A still held VERIFY_LGAPI_CLAIM_PAUSE (lock did not block B)"
fi
echo "B blocked on lock during A's pause pid=${b_pid}"

wait "${a_pid}"
wait "${b_pid}"
echo "--- A ---"; cat "${a_out}"
echo "--- B ---"; cat "${b_out}"
if ! grep -q 'owners=2' "${b_out}"; then
  fail "B did not register as owners=2"
fi
if ! grep -qx 'race-a' "${LANGGRAPH_API_OWNED_MARKER}" || ! grep -qx 'race-b' "${LANGGRAPH_API_OWNED_MARKER}"; then
  fail "marker missing race-a or race-b"
fi
printf 'sentinel-b\n' > "${LANGGRAPH_API_DIR}/SENTINEL-B.txt"
cleanup_as race-a
if [[ ! -f "${LANGGRAPH_API_DIR}/SENTINEL-B.txt" ]]; then
  fail "A's cleanup deleted B's files"
fi
grep -qx 'sentinel-b' "${LANGGRAPH_API_DIR}/SENTINEL-B.txt"
grep -qx 'race-b' "${LANGGRAPH_API_OWNED_MARKER}"
echo "PASS: B registered (owners=2) and survived A's cleanup"
cleanup_as race-b
if [[ -e "${LANGGRAPH_API_DIR}" ]]; then
  fail "last-owner cleanup left ${LANGGRAPH_API_DIR}"
fi
rm -rf "${work}"
echo "PASS: create-before-mark race with lock"
