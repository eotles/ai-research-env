#!/usr/bin/env bash

set -Eeuo pipefail

# Generate the canonical Linux x86-64 CUDA lockfile.
#
# By default, seed conda-lock with the existing canonical lockfile. conda-lock
# then treats the existing solution as a constraint, which keeps unrelated
# packages stable when a dependency is added or adjusted.
#
# Usage:
#
#   bash scripts/generate-gpu-lockfile.sh
#   bash scripts/generate-gpu-lockfile.sh /path/to/candidate-conda-lock-gpu.yml
#   bash scripts/generate-gpu-lockfile.sh --refresh /path/to/candidate-conda-lock-gpu.yml
#
# --refresh deliberately solves from scratch and is intended for scheduled
# dependency-drift monitoring or intentional broad dependency refreshes.

SCRIPT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")"
  pwd
)"

REPO_ROOT="$(
  cd "${SCRIPT_DIR}/.."
  pwd
)"

ENVIRONMENT_FILE="${REPO_ROOT}/environment-gpu.yml"
CANONICAL_LOCK="${REPO_ROOT}/conda-lock-gpu.yml"
OUTPUT_FILE="${CANONICAL_LOCK}"
REFRESH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --refresh)
      REFRESH=true
      shift
      ;;
    -h|--help)
      sed -n '3,17p' "$0"
      exit 0
      ;;
    -*)
      echo "Error: unknown option: $1" >&2
      exit 2
      ;;
    *)
      OUTPUT_FILE="$1"
      shift
      if [[ $# -gt 0 ]]; then
        echo "Error: only one output path may be supplied." >&2
        exit 2
      fi
      ;;
  esac
done

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

if [[ "${REFRESH}" == false ]] && [[ -s "${CANONICAL_LOCK}" ]]; then
  cp "${CANONICAL_LOCK}" "${TEMP_FILE}"
  echo "Lock strategy:    preserve existing compatible package solutions"
else
  echo "Lock strategy:    fresh solve"
fi

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
