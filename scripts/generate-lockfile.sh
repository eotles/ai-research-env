#!/usr/bin/env bash

set -Eeuo pipefail

# Generate the canonical multi-platform unified conda-lock file.
#
# Usage:
#
#   bash scripts/generate-lockfile.sh
#
# writes:
#
#   ./conda-lock.yml
#
# Or:
#
#   bash scripts/generate-lockfile.sh /path/to/candidate-conda-lock.yml

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd
)"

REPO_ROOT="$(
  cd "${SCRIPT_DIR}/.."
  pwd
)"

ENVIRONMENT_FILE="${REPO_ROOT}/environment.yml"
OUTPUT_FILE="${1:-${REPO_ROOT}/conda-lock.yml}"


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
# Generate atomically
# -----------------------------------------------------------------------------

mkdir -p "$(dirname "${OUTPUT_FILE}")"

TEMP_FILE="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"

cleanup() {
  rm -f "${TEMP_FILE}"
}

trap cleanup EXIT

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Output lockfile:  ${OUTPUT_FILE}"
echo "Conda executable: ${MAMBA_EXE}"

"${MAMBA_EXE}" run -n base conda-lock \
  --conda "${MAMBA_EXE}" \
  --without-cuda \
  --log-level INFO \
  --file "${ENVIRONMENT_FILE}" \
  --kind lock \
  --lockfile "${TEMP_FILE}"

if [[ ! -s "${TEMP_FILE}" ]]; then
  echo "Error: conda-lock completed but produced no lockfile." >&2
  exit 1
fi

mv "${TEMP_FILE}" "${OUTPUT_FILE}"

echo "Unified lockfile generated successfully:"
echo "  ${OUTPUT_FILE}"
