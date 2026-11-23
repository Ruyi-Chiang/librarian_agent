#!/usr/bin/env bash
# Shared paths and guards for verify-librarian helpers.
# Source only: `. helpers/common.sh` — do not execute this file.

set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${_THIS_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd)"

LAST_RUN_FILE="/tmp/verify-librarian.last-run"
if [[ -z "${VERIFY_RUN_ID:-}" && -f "${LAST_RUN_FILE}" ]]; then
  VERIFY_RUN_ID="$(tr -d '[:space:]' < "${LAST_RUN_FILE}")"
fi
if [[ -z "${VERIFY_RUN_ID:-}" ]]; then
  VERIFY_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi

VERIFY_SCRATCH="${VERIFY_SCRATCH:-/tmp/verify-librarian-${VERIFY_RUN_ID}}"
VERIFY_EVIDENCE="${VERIFY_EVIDENCE:-${REPO_ROOT}/evidence/runs/${VERIFY_RUN_ID}}"
VERIFY_VENV="${VERIFY_VENV:-${REPO_ROOT}/.venv}"
SCRATCH_PREFIX="/tmp/verify-librarian-"
RUN_MARKER="${VERIFY_SCRATCH}/.verify-librarian-run"
# langgraph-runtime-inmem hardcodes cwd/.langgraph_api (no redirect env/flag).
LANGGRAPH_API_DIR="${REPO_ROOT}/.langgraph_api"
LANGGRAPH_API_OWNED_MARKER="${LANGGRAPH_API_DIR}/.verify-librarian-owned"
# Lock lives outside .langgraph_api so last-owner rm -rf cannot drop it.
LANGGRAPH_API_LOCK="/tmp/verify-librarian-lgapi.lock"

PY="${VERIFY_VENV}/bin/python"
PYTEST="${VERIFY_VENV}/bin/pytest"
LANGGRAPH_BIN="${VERIFY_VENV}/bin/langgraph"

export SKILL_DIR REPO_ROOT VERIFY_RUN_ID VERIFY_SCRATCH VERIFY_EVIDENCE VERIFY_VENV
export PY PYTEST LANGGRAPH_BIN SCRATCH_PREFIX RUN_MARKER LAST_RUN_FILE
export LANGGRAPH_API_DIR LANGGRAPH_API_OWNED_MARKER LANGGRAPH_API_LOCK

canonicalize_paths() {
  if [[ -z "${VERIFY_SCRATCH}" ]]; then
    echo "VERIFY_SCRATCH is empty" >&2
    return 2
  fi
  local py_bin="${PY}"
  if [[ ! -x "${py_bin}" ]]; then
    py_bin="python3"
  fi
  VERIFY_SCRATCH="$("${py_bin}" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${VERIFY_SCRATCH}")"
  VERIFY_EVIDENCE="$("${py_bin}" -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "${VERIFY_EVIDENCE}")"
  SCRATCH_PREFIX="$("${py_bin}" -c 'import os; print(os.path.realpath("/tmp"))')/verify-librarian-"
  RUN_MARKER="${VERIFY_SCRATCH}/.verify-librarian-run"
  export VERIFY_SCRATCH VERIFY_EVIDENCE RUN_MARKER
  case "${VERIFY_EVIDENCE}" in
    "${VERIFY_SCRATCH}"|"${VERIFY_SCRATCH}"/*)
      echo "refuse: VERIFY_EVIDENCE must not live under VERIFY_SCRATCH (${VERIFY_EVIDENCE})" >&2
      return 2
      ;;
  esac
}

require_isolated_scratch() {
  canonicalize_paths || return $?
  case "${VERIFY_SCRATCH}" in
    "${SCRATCH_PREFIX}"?*)
      ;;
    *)
      echo "refuse: VERIFY_SCRATCH must resolve under ${SCRATCH_PREFIX}<run-id>, got ${VERIFY_SCRATCH}" >&2
      return 2
      ;;
  esac
}

scratch_marker_run_id() {
  if [[ -f "${RUN_MARKER}" ]]; then
    tr -d '[:space:]' < "${RUN_MARKER}"
  fi
}

prepare_scratch() {
  require_isolated_scratch
  mkdir -p "${VERIFY_EVIDENCE}"
  if [[ -e "${VERIFY_SCRATCH}" ]]; then
    if [[ ! -d "${VERIFY_SCRATCH}" ]]; then
      echo "refuse: VERIFY_SCRATCH exists and is not a directory: ${VERIFY_SCRATCH}" >&2
      return 2
    fi
    local existing
    existing="$(scratch_marker_run_id)"
    if [[ -z "${existing}" ]]; then
      echo "refuse: ${VERIFY_SCRATCH} already exists without this run's marker; will not claim it" >&2
      return 2
    fi
    if [[ "${existing}" != "${VERIFY_RUN_ID}" ]]; then
      echo "refuse: ${VERIFY_SCRATCH} belongs to run ${existing}, not ${VERIFY_RUN_ID}" >&2
      return 2
    fi
  else
    mkdir -p "${VERIFY_SCRATCH}"
  fi
  printf '%s\n' "${VERIFY_RUN_ID}" > "${RUN_MARKER}"
  printf '%s\n' "${VERIFY_RUN_ID}" > "${LAST_RUN_FILE}"
}

require_our_scratch() {
  require_isolated_scratch
  local existing
  existing="$(scratch_marker_run_id)"
  if [[ -z "${existing}" ]]; then
    echo "refuse: expected ${RUN_MARKER} from launch; run helpers/launch.sh first" >&2
    return 2
  fi
  if [[ "${existing}" != "${VERIFY_RUN_ID}" ]]; then
    echo "refuse: scratch marker is ${existing}, this run is ${VERIFY_RUN_ID}" >&2
    return 2
  fi
}

# Test-only: sleep between mkdir and the owner-marker write so How to verify
# can hold run A in the create-before-mark window. The lock stays held.
_langgraph_api_claim_pause() {
  local pause="${VERIFY_LGAPI_CLAIM_PAUSE:-}"
  if [[ -z "${pause}" ]]; then
    return 0
  fi
  echo "langgraph_api_claim_pause seconds=${pause} path=${LANGGRAPH_API_DIR}"
  sleep "${pause}"
}

# Serialize claim and cleanup outside .langgraph_api so mkdir + marker
# write cannot interleave, and last-owner rm -rf cannot drop the lock.
# Prefer flock on a lock file; fall back to mkdir if flock is missing.
_langgraph_api_with_flock() {
  local lockfile="${LANGGRAPH_API_LOCK}"
  local lgapi_lock_fd
  if [[ -d "${lockfile}" ]]; then
    rmdir "${lockfile}" 2>/dev/null || true
  fi
  : >> "${lockfile}"
  exec {lgapi_lock_fd}>"${lockfile}"
  flock "${lgapi_lock_fd}"
  "$@"
  local status=$?
  exec {lgapi_lock_fd}>&-
  return "${status}"
}

_langgraph_api_with_mkdir_lock() {
  local lockdir="${LANGGRAPH_API_LOCK}.d"
  local i
  for i in $(seq 1 50); do
    if mkdir "${lockdir}" 2>/dev/null; then
      "$@"
      local status=$?
      rmdir "${lockdir}" 2>/dev/null || true
      return "${status}"
    fi
    sleep 0.1
  done
  echo "refuse: could not lock ${lockdir}" >&2
  return 2
}

_langgraph_api_with_lock() {
  if command -v flock >/dev/null 2>&1; then
    _langgraph_api_with_flock "$@"
    return
  fi
  _langgraph_api_with_mkdir_lock "$@"
}

_langgraph_api_owner_count() {
  if [[ ! -f "${LANGGRAPH_API_OWNED_MARKER}" ]]; then
    echo 0
    return 0
  fi
  grep -c . "${LANGGRAPH_API_OWNED_MARKER}" || true
}

_claim_langgraph_api_dir() {
  if [[ -e "${LANGGRAPH_API_DIR}" && ! -d "${LANGGRAPH_API_DIR}" ]]; then
    echo "refuse: ${LANGGRAPH_API_DIR} exists and is not a directory" >&2
    return 2
  fi
  if [[ ! -d "${LANGGRAPH_API_DIR}" ]]; then
    mkdir "${LANGGRAPH_API_DIR}"
    _langgraph_api_claim_pause
    printf '%s\n' "${VERIFY_RUN_ID}" > "${LANGGRAPH_API_OWNED_MARKER}"
    echo "langgraph_api_owned path=${LANGGRAPH_API_DIR} owners=1"
    return 0
  fi
  if [[ ! -f "${LANGGRAPH_API_OWNED_MARKER}" ]]; then
    echo "langgraph_api_unmarked path=${LANGGRAPH_API_DIR}"
    return 0
  fi
  if ! grep -qxF "${VERIFY_RUN_ID}" "${LANGGRAPH_API_OWNED_MARKER}"; then
    printf '%s\n' "${VERIFY_RUN_ID}" >> "${LANGGRAPH_API_OWNED_MARKER}"
  fi
  echo "langgraph_api_owned path=${LANGGRAPH_API_DIR} owners=$(_langgraph_api_owner_count)"
}

_remove_owned_langgraph_api_dir() {
  if [[ ! -f "${LANGGRAPH_API_OWNED_MARKER}" ]]; then
    if [[ -e "${LANGGRAPH_API_DIR}" ]]; then
      echo "langgraph_api_left path=${LANGGRAPH_API_DIR}"
    else
      echo "langgraph_api_absent"
    fi
    return 0
  fi
  local remaining
  remaining="$(grep -vxF "${VERIFY_RUN_ID}" "${LANGGRAPH_API_OWNED_MARKER}" || true)"
  if [[ -z "${remaining}" ]]; then
    rm -rf "${LANGGRAPH_API_DIR}"
    echo "langgraph_api_removed path=${LANGGRAPH_API_DIR}"
    return 0
  fi
  printf '%s\n' "${remaining}" > "${LANGGRAPH_API_OWNED_MARKER}"
  echo "langgraph_api_left path=${LANGGRAPH_API_DIR} remaining_owners=$(_langgraph_api_owner_count)"
}

# Claim cwd/.langgraph_api only when absent or already marked by this harness.
# A pre-existing unmarked directory (developer Studio cache) is left untouched.
# Concurrent verify runs share the directory; each run ID is recorded so
# cleanup removes it only after the last owner stops.
claim_langgraph_api_dir() {
  if [[ "${VERIFY_LGAPI_SKIP_LOCK:-}" == "1" ]]; then
    _claim_langgraph_api_dir
    return
  fi
  _langgraph_api_with_lock _claim_langgraph_api_dir
}

# Remove .langgraph_api only when this harness owns it and this run is the
# last remaining owner. Other active verify runs keep the shared cache.
remove_owned_langgraph_api_dir() {
  if [[ "${VERIFY_LGAPI_SKIP_LOCK:-}" == "1" ]]; then
    _remove_owned_langgraph_api_dir
    return
  fi
  _langgraph_api_with_lock _remove_owned_langgraph_api_dir
}

capture() {
  local name="$1"
  shift
  local out="${VERIFY_EVIDENCE}/${name}.stdout.txt"
  local err="${VERIFY_EVIDENCE}/${name}.stderr.txt"
  local meta="${VERIFY_EVIDENCE}/${name}.meta.txt"
  local status=0
  set +e
  "$@" >"${out}" 2>"${err}"
  status=$?
  set -e
  {
    echo "command=$*"
    echo "exit=${status}"
    echo "cwd=${PWD}"
    echo "run_id=${VERIFY_RUN_ID}"
    echo "scratch=${VERIFY_SCRATCH}"
    echo "evidence=${VERIFY_EVIDENCE}"
  } >"${meta}"
  return "${status}"
}

append_summary() {
  local feature="$1"
  local status="$2"
  local note="$3"
  local summary="${VERIFY_EVIDENCE}/SUMMARY.md"
  mkdir -p "${VERIFY_EVIDENCE}"
  if [[ ! -f "${summary}" ]]; then
    printf '%s\n\n' "# verify-librarian run ${VERIFY_RUN_ID}" >"${summary}"
  fi
  printf -- '- feature=%s status=%s %s\n' "${feature}" "${status}" "${note}" >>"${summary}"
}

langgraph_url() {
  local port_file="${VERIFY_SCRATCH}/langgraph.port"
  local port="${VERIFY_LANGGRAPH_PORT:-}"
  if [[ -z "${port}" && -f "${port_file}" ]]; then
    port="$(tr -d '[:space:]' < "${port_file}")"
  fi
  port="${port:-20247}"
  printf 'http://127.0.0.1:%s' "${port}"
}
