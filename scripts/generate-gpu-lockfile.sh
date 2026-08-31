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
# path elsewhere on disk. Use a temporary directory rather than mktemp's file
# mode so a fresh solve receives a path that does not already exist. conda-lock
# 3.0.4 tries to parse any existing --lockfile as YAML, including an empty
# mktemp-created file, which fails before dependency resolution starts.
CANONICAL_DIR="$(
  cd "$(dirname "${CANONICAL_LOCK}")"
  pwd
)"
mkdir -p "$(dirname "${OUTPUT_FILE}")"
TEMP_DIR="$(mktemp -d "${CANONICAL_DIR}/.conda-lock-gpu.tmp.XXXXXX")"
TEMP_FILE="${TEMP_DIR}/conda-lock-gpu.yml"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

normalize_lock_metadata() {
  local lock_file="$1"
  local generated_name="${2:-}"

  python - "${lock_file}" "${generated_name}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
generated_name = sys.argv[2]
text = path.read_text()

source_pattern = re.compile(r"(?m)^  sources:\n(?:  - .*\n)+")
text, count = source_pattern.subn(
    "  sources:\n  - environment-gpu.yml\n",
    text,
    count=1,
)
if count != 1:
    raise SystemExit("Could not normalize metadata.sources in GPU lockfile")

if generated_name:
    text = text.replace(generated_name, "conda-lock-gpu.yml")

text = re.sub(
    r"(?m)^#     conda-lock -f .*environment-gpu\.yml --lockfile conda-lock-gpu\.yml$",
    "#     conda-lock -f environment-gpu.yml --lockfile conda-lock-gpu.yml",
    text,
)

path.write_text(text)
PY
}

echo "Environment file: ${ENVIRONMENT_FILE}"
echo "Output lockfile:  ${OUTPUT_FILE}"
echo "Conda executable: ${MAMBA_EXE}"

if [[ "${REFRESH}" == false ]] && [[ -s "${CANONICAL_LOCK}" ]]; then
  cp "${CANONICAL_LOCK}" "${TEMP_FILE}"
  # Historical lockfiles may contain source/header paths that reflect the
  # directory where they were generated. Normalize them before using the old
  # lock as package constraints.
  normalize_lock_metadata "${TEMP_FILE}" "$(basename "${TEMP_FILE}")"
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

# conda-lock embeds the supplied lockfile name into instructional comments and
# records source paths relative to the generated lock. Normalize those fields so
# the canonical file is byte-stable even though generation uses a temporary
# directory for atomicity.
normalize_lock_metadata "${TEMP_FILE}" "$(basename "${TEMP_FILE}")"

mv "${TEMP_FILE}" "${OUTPUT_FILE}"

echo "Canonical GPU lockfile generated successfully:"
echo "  ${OUTPUT_FILE}"
