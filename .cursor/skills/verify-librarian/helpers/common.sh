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

PY="${VERIFY_VENV}/bin/python"
PYTEST="${VERIFY_VENV}/bin/pytest"
LANGGRAPH_BIN="${VERIFY_VENV}/bin/langgraph"

export SKILL_DIR REPO_ROOT VERIFY_RUN_ID VERIFY_SCRATCH VERIFY_EVIDENCE VERIFY_VENV
export PY PYTEST LANGGRAPH_BIN SCRATCH_PREFIX RUN_MARKER LAST_RUN_FILE

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
    echo "doctor/drive expected ${RUN_MARKER} from launch; run helpers/launch.sh first" >&2
    return 2
  fi
  if [[ "${existing}" != "${VERIFY_RUN_ID}" ]]; then
    echo "refuse: scratch marker is ${existing}, this run is ${VERIFY_RUN_ID}" >&2
    return 2
  fi
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
