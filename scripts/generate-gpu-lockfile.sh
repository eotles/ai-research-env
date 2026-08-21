#!/usr/bin/env bash

set -Eeuo pipefail

# Generate the canonical Linux x86-64 CUDA lockfile.
#
# Usage:
#
#   bash scripts/generate-gpu-lockfile.sh
#
# writes:
#
#   ./conda-lock-gpu.yml
#
# Or:
#
#   bash scripts/generate-gpu-lockfile.sh /path/to/candidate-conda-lock-gpu.yml

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd
)"

REPO_ROOT="$(
  cd "${SCRIPT_DIR}/.."
  pwd
)"

ENVIRONMENT_FILE="${REPO_ROOT}/environment-gpu.yml"
OUTPUT_FILE="${1:-${REPO_ROOT}/conda-lock-gpu.yml}"

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

OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
mkdir -p "${OUTPUT_DIR}"

TEMP_DIR="$(
  mktemp -d "${OUTPUT_DIR}/.conda-lock-gpu.tmp.XXXXXX"
)"
TEMP_FILE="${TEMP_DIR}/conda-lock-gpu.yml"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Output lockfile:  ${OUTPUT_FILE}"
echo "Conda executable: ${MAMBA_EXE}"

# Do not pass --without-cuda here. The purpose of this target is to resolve and
# retain the CUDA runtime selected by pytorch-cuda=12.4.
"${MAMBA_EXE}" run -n base conda-lock \
  --conda "${MAMBA_EXE}" \
  --log-level INFO \
  --file "${ENVIRONMENT_FILE}" \
  --kind lock \
  --lockfile "${TEMP_FILE}"

if [[ ! -s "${TEMP_FILE}" ]]; then
  echo "Error: conda-lock completed but produced no GPU lockfile." >&2
  exit 1
fi

mv "${TEMP_FILE}" "${OUTPUT_FILE}"

echo "Canonical GPU lockfile generated successfully:"
echo "  ${OUTPUT_FILE}"
