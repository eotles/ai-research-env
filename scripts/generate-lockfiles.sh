#!/usr/bin/env bash

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Generate platform-specific explicit conda lockfiles.
#
# Usage:
#
#   bash scripts/generate-lockfiles.sh
#
# Generates locks for all supported platforms.
#
# Or:
#
#   bash scripts/generate-lockfiles.sh linux-64 osx-arm64
#
# Generates locks only for the specified platforms.
#
# Environment variables:
#
#   MAMBA_EXE
#       Path to micromamba, mamba, or conda.
#       setup-micromamba normally defines this automatically in CI.
#
#   LOCK_TIMEOUT
#       Per-platform solver timeout.
#       Default: 10m
#
#   LOCK_SUMMARY_FILE
#       TSV file containing platform, status, duration, and exit code.
#       Default: a temporary file.
#
# Notes:
#
#   These are the repository's existing explicit conda lockfiles.
#   They are not intended to validate installation of pip dependencies.
#   Complete mixed conda/PyPI installation is tested separately by
#   environment-install-check.yml.
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Resolve repository paths
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd
)"

REPO_ROOT="$(
  cd "${SCRIPT_DIR}/.."
  pwd
)"

ENVIRONMENT_FILE="${REPO_ROOT}/environment.yml"
LOCK_DIR="${REPO_ROOT}/locks"

mkdir -p "${LOCK_DIR}"


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

LOCK_TIMEOUT="${LOCK_TIMEOUT:-10m}"
LOCK_SUMMARY_FILE="${LOCK_SUMMARY_FILE:-$(mktemp)}"

DEFAULT_PLATFORMS=(
  linux-64
  linux-aarch64
  osx-64
  osx-arm64
  win-64
)

if [[ "$#" -gt 0 ]]; then
  PLATFORMS=("$@")
else
  PLATFORMS=("${DEFAULT_PLATFORMS[@]}")
fi


# -----------------------------------------------------------------------------
# Locate the conda-compatible executable
# -----------------------------------------------------------------------------

if [[ -z "${MAMBA_EXE:-}" ]]; then
  if command -v micromamba >/dev/null 2>&1; then
    MAMBA_EXE="$(command -v micromamba)"
  elif command -v mamba >/dev/null 2>&1; then
    MAMBA_EXE="$(command -v mamba)"
  elif command -v conda >/dev/null 2>&1; then
    MAMBA_EXE="$(command -v conda)"
  else
    echo "Error: could not find micromamba, mamba, or conda." >&2
    exit 1
  fi
fi


# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------

if [[ ! -f "${ENVIRONMENT_FILE}" ]]; then
  echo "Error: environment file not found: ${ENVIRONMENT_FILE}" >&2
  exit 1
fi

if ! "${MAMBA_EXE}" run -n base conda-lock --version >/dev/null 2>&1; then
  echo "Error: conda-lock is not available in the base environment." >&2
  exit 1
fi


# -----------------------------------------------------------------------------
# Portable timeout helper
#
# GNU/Linux normally provides `timeout`.
# macOS users may have GNU coreutils installed as `gtimeout`.
# If neither exists, run without a per-platform timeout.
# -----------------------------------------------------------------------------

run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "${LOCK_TIMEOUT}" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${LOCK_TIMEOUT}" "$@"
  else
    echo "Warning: timeout/gtimeout not found; running without a per-platform timeout." >&2
    "$@"
  fi
}


# -----------------------------------------------------------------------------
# Initialize summary
# -----------------------------------------------------------------------------

printf "platform\tstatus\tduration_seconds\texit_code\n" > "${LOCK_SUMMARY_FILE}"

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Lock directory:   ${LOCK_DIR}"
echo "Conda executable: ${MAMBA_EXE}"
echo "Timeout:          ${LOCK_TIMEOUT}"
echo "Platforms:        ${PLATFORMS[*]}"
echo


# -----------------------------------------------------------------------------
# Generate each platform lock independently
# -----------------------------------------------------------------------------

FAILED=0

for platform in "${PLATFORMS[@]}"; do
  echo "::group::Generating lockfile for ${platform}"

  START_TIME="$(date +%s)"
  TEMP_DIR="$(mktemp -d)"

  TEMP_TEMPLATE="${TEMP_DIR}/conda-{platform}.lock"
  FINAL_LOCK="${LOCK_DIR}/conda-${platform}.lock"

  set +e

  run_with_timeout \
    "${MAMBA_EXE}" run -n base conda-lock \
      --conda "${MAMBA_EXE}" \
      --without-cuda \
      --log-level INFO \
      --file "${ENVIRONMENT_FILE}" \
      --platform "${platform}" \
      --kind explicit \
      --filename-template "${TEMP_TEMPLATE}"

  STATUS=$?

  set -e

  END_TIME="$(date +%s)"
  ELAPSED="$((END_TIME - START_TIME))"

  TEMP_LOCK="${TEMP_DIR}/conda-${platform}.lock"

  if [[ "${STATUS}" -eq 0 ]]; then
    if [[ ! -s "${TEMP_LOCK}" ]]; then
      echo "Error: solver exited successfully but no lockfile was produced." >&2
      STATUS=1
    else
      mv "${TEMP_LOCK}" "${FINAL_LOCK}"

      echo "✓ ${platform}"
      echo "  output: ${FINAL_LOCK}"
      echo "  elapsed: ${ELAPSED}s"

      printf "%s\tPASS\t%s\t0\n" \
        "${platform}" \
        "${ELAPSED}" \
        >> "${LOCK_SUMMARY_FILE}"
    fi
  fi

  if [[ "${STATUS}" -ne 0 ]]; then
    FAILED=1

    if [[ "${STATUS}" -eq 124 ]]; then
      echo "::error::${platform} timed out after ${LOCK_TIMEOUT}."
      RESULT="TIMEOUT"
    else
      echo "::error::${platform} failed with exit code ${STATUS}."
      RESULT="FAIL"
    fi

    printf "%s\t%s\t%s\t%s\n" \
      "${platform}" \
      "${RESULT}" \
      "${ELAPSED}" \
      "${STATUS}" \
      >> "${LOCK_SUMMARY_FILE}"
  fi

  rm -rf "${TEMP_DIR}"

  echo "::endgroup::"
done


# -----------------------------------------------------------------------------
# Human-readable summary
# -----------------------------------------------------------------------------

echo
echo "Lockfile generation summary:"
echo

column -t -s $'\t' "${LOCK_SUMMARY_FILE}" 2>/dev/null \
  || cat "${LOCK_SUMMARY_FILE}"

echo

if [[ "${FAILED}" -ne 0 ]]; then
  echo "One or more platform lockfile solves failed." >&2
  exit 1
fi

echo "All requested platform lockfiles generated successfully."
