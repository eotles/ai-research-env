#!/usr/bin/env bash

set -Eeuo pipefail

# Generate the canonical multi-platform conda lockfile.
#
# By default, seed conda-lock with the existing canonical lockfile. conda-lock
# then treats the existing solution as a constraint, which keeps unrelated
# packages stable when a dependency is added or adjusted.
#
# Usage:
#
#   bash scripts/generate-lockfile.sh
#   bash scripts/generate-lockfile.sh /path/to/candidate-conda-lock.yml
#   bash scripts/generate-lockfile.sh --refresh /path/to/candidate-conda-lock.yml
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

ENVIRONMENT_FILE="${REPO_ROOT}/environment.yml"
CANONICAL_LOCK="${REPO_ROOT}/conda-lock.yml"
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

if [[ ! -f "${ENVIRONMENT_FILE}" ]]; then
  echo "Error: environment file not found: ${ENVIRONMENT_FILE}" >&2
  exit 1
fi

if ! "${MAMBA_EXE}" run -n base conda-lock --version >/dev/null 2>&1; then
  echo "Error: conda-lock is not available in the base environment." >&2
  exit 1
fi

# Always process the working lock beside the canonical lock. Existing lock source
# metadata is relative to that location, while OUTPUT_FILE may be a CI artifact
# path elsewhere on disk.
CANONICAL_DIR="$(
  cd "$(dirname "${CANONICAL_LOCK}")"
  pwd
)"
mkdir -p "$(dirname "${OUTPUT_FILE}")"
TEMP_FILE="$(mktemp "${CANONICAL_DIR}/.conda-lock.tmp.XXXXXX.yml")"

cleanup() {
  rm -f "${TEMP_FILE}"
}
trap cleanup EXIT

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Output lockfile:  ${OUTPUT_FILE}"
echo "Conda executable: ${MAMBA_EXE}"

source_args=(--file "${ENVIRONMENT_FILE}")
if [[ "${REFRESH}" == false ]] && [[ -s "${CANONICAL_LOCK}" ]]; then
  cp "${CANONICAL_LOCK}" "${TEMP_FILE}"
  # Let conda-lock read the source path already recorded by the canonical lock,
  # which preserves its source metadata spelling and existing package solution.
  source_args=()
  echo "Lock strategy:    preserve existing compatible package solutions"
else
  echo "Lock strategy:    fresh solve"
fi

"${MAMBA_EXE}" run -n base conda-lock \
  --conda "${MAMBA_EXE}" \
  --without-cuda \
  --log-level INFO \
  "${source_args[@]}" \
  --kind lock \
  --lockfile "${TEMP_FILE}"

if [[ ! -s "${TEMP_FILE}" ]]; then
  echo "Error: conda-lock completed but produced no lockfile." >&2
  exit 1
fi

mv "${TEMP_FILE}" "${OUTPUT_FILE}"

echo "Canonical lockfile generated successfully:"
echo "  ${OUTPUT_FILE}"
