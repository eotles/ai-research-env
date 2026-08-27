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

# Always process the working lock beside the canonical lock. conda-lock records
# source paths relative to the lockfile, while OUTPUT_FILE may be a CI artifact
# path elsewhere on disk.
CANONICAL_DIR="$(
  cd "$(dirname "${CANONICAL_LOCK}")"
  pwd
)"
mkdir -p "$(dirname "${OUTPUT_FILE}")"
TEMP_FILE="$(mktemp "${CANONICAL_DIR}/.conda-lock-gpu.tmp.XXXXXX.yml")"

cleanup() {
  rm -f "${TEMP_FILE}"
}
trap cleanup EXIT

normalize_seed_source() {
  local lock_file="$1"
  local source_name="$2"

  python - "${lock_file}" "${source_name}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source_name = sys.argv[2]
text = path.read_text()
pattern = re.compile(r"(?m)^  sources:\n(?:  - .*\n)+")
replacement = f"  sources:\n  - {source_name}\n"
updated, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit("Could not normalize metadata.sources in seeded lockfile")
path.write_text(updated)
PY
}

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Output lockfile:  ${OUTPUT_FILE}"
echo "Conda executable: ${MAMBA_EXE}"

if [[ "${REFRESH}" == false ]] && [[ -s "${CANONICAL_LOCK}" ]]; then
  cp "${CANONICAL_LOCK}" "${TEMP_FILE}"
  # Historical lockfiles may contain source paths that reflect the directory in
  # which they were originally generated. Normalize that metadata before using
  # the old lock as package constraints, then parse the current source explicitly.
  normalize_seed_source "${TEMP_FILE}" "environment-gpu.yml"
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
