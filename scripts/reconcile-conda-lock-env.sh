#!/usr/bin/env bash

set -Eeuo pipefail

# Incrementally reconcile an existing micromamba environment with a unified
# conda-lock file. The lock is rendered to an exact version/build environment
# specification, then micromamba updates and prunes only the changed packages.
# A conda-package validation step confirms the resulting environment matches the
# exact URLs selected by the lock. Callers should fall back to a clean rebuild if
# this script fails.

LOCK_FILE=""
ENV_NAME=""
LOCK_TOOLS_ENV=""
PLATFORM="linux-64"

usage() {
  cat <<'EOF'
Usage: reconcile-conda-lock-env.sh --lock FILE --name ENV --lock-tools-env ENV [options]

Options:
  --lock FILE            Unified conda-lock file.
  --name ENV             Existing micromamba environment to reconcile.
  --lock-tools-env ENV   Environment containing conda-lock.
  --platform PLATFORM    Lock platform to render (default: linux-64).
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock)
      LOCK_FILE="$2"
      shift 2
      ;;
    --name)
      ENV_NAME="$2"
      shift 2
      ;;
    --lock-tools-env)
      LOCK_TOOLS_ENV="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${LOCK_FILE}" || -z "${ENV_NAME}" || -z "${LOCK_TOOLS_ENV}" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "${LOCK_FILE}" ]]; then
  echo "Error: lockfile not found: ${LOCK_FILE}" >&2
  exit 1
fi

if ! command -v micromamba >/dev/null 2>&1; then
  echo "Error: micromamba is required." >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

pushd "${TEMP_DIR}" >/dev/null
micromamba run -n "${LOCK_TOOLS_ENV}" \
  conda-lock render \
  --kind env \
  --platform "${PLATFORM}" \
  "${LOCK_FILE}"

micromamba run -n "${LOCK_TOOLS_ENV}" \
  conda-lock render \
  --kind explicit \
  --platform "${PLATFORM}" \
  "${LOCK_FILE}"
popd >/dev/null

ENV_LOCK="${TEMP_DIR}/conda-${PLATFORM}.lock.yml"
EXPLICIT_LOCK="${TEMP_DIR}/conda-${PLATFORM}.lock"

if [[ ! -s "${ENV_LOCK}" || ! -s "${EXPLICIT_LOCK}" ]]; then
  echo "Error: conda-lock did not render the expected platform lockfiles." >&2
  exit 1
fi

echo "Incrementally reconciling ${ENV_NAME} from the canonical lock ..."
micromamba env update \
  --yes \
  --name "${ENV_NAME}" \
  --file "${ENV_LOCK}" \
  --prune

# Validate that every conda package selected by the unified lock is installed as
# the same exact package URL/build. Strip hashes because micromamba list
# --explicit reports package URLs without conda-lock's fragment hashes.
grep -E '^https?://' "${EXPLICIT_LOCK}" \
  | sed 's/#.*$//' \
  | sort -u > "${TEMP_DIR}/expected-conda.txt"

micromamba list --name "${ENV_NAME}" --explicit \
  | grep -E '^https?://' \
  | sed 's/#.*$//' \
  | sort -u > "${TEMP_DIR}/installed-conda.txt"

if ! diff -u "${TEMP_DIR}/expected-conda.txt" "${TEMP_DIR}/installed-conda.txt"; then
  echo "Error: incremental reconcile did not exactly match locked conda packages." >&2
  exit 1
fi

micromamba run -n "${ENV_NAME}" python -m pip check

echo "Incremental conda-lock reconciliation succeeded."
