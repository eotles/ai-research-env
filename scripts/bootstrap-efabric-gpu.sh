#!/usr/bin/env bash

set -Eeuo pipefail

# Manually bootstrap/update and enter the canonical ai-research-env GPU
# environment on an EFabric Workspace.
#
# Each invocation:
#   1. Clones or fast-forwards ai-research-env to the requested branch.
#   2. Reconciles ai-research-env-gpu only when conda-lock-gpu.yml changes.
#   3. Keeps the micromamba environment in persistent EFabric home storage.
#   4. Starts an interactive Bash shell with the GPU environment activated.
#
# Nothing is installed into shell startup files and nothing runs automatically
# at login. The user explicitly launches the environment with this script.

REPO_URL="${AI_RESEARCH_ENV_REPO_URL:-https://github.com/eotles/ai-research-env.git}"
REPO_DIR="${AI_RESEARCH_ENV_REPO_DIR:-${HOME}/src/ai-research-env}"
BRANCH="${AI_RESEARCH_ENV_BRANCH:-main}"
ENV_NAME="${AI_RESEARCH_ENV_GPU_ENV_NAME:-ai-research-env-gpu}"
LOCK_TOOLS_ENV="${AI_RESEARCH_ENV_LOCK_TOOLS_ENV_NAME:-ai-env-lock-tools}"
STATE_DIR="${AI_RESEARCH_ENV_STATE_DIR:-${HOME}/.ai-research-env}"

export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-${HOME}/.micromamba}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-${HOME}/.cache/matplotlib}"

FORCE_REINSTALL=false
RUN_SMOKE_TEST=false
NO_SHELL=false
REEXECUTED="${AI_RESEARCH_ENV_BOOTSTRAP_REEXEC:-0}"
START_DIR="${AI_RESEARCH_ENV_START_DIR:-${PWD}}"

ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Usage: bootstrap-efabric-gpu.sh [options]

Update ai-research-env, reconcile the canonical GPU environment, and launch an
interactive Bash shell with that environment activated.

Options:
  --force-reinstall  Recreate the GPU environment even if the lock hash matches.
  --smoke-test       Run the general and real-GPU smoke tests before launching.
  --no-shell         Update/reconcile the environment, then exit without a shell.
  --branch NAME      Track a branch other than main.
  -h, --help         Show this help.

Environment overrides:
  AI_RESEARCH_ENV_REPO_URL
  AI_RESEARCH_ENV_REPO_DIR
  AI_RESEARCH_ENV_BRANCH
  AI_RESEARCH_ENV_GPU_ENV_NAME
  AI_RESEARCH_ENV_LOCK_TOOLS_ENV_NAME
  AI_RESEARCH_ENV_STATE_DIR
  AI_RESEARCH_ENV_START_DIR
  MAMBA_ROOT_PREFIX
  MPLCONFIGDIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-reinstall)
      FORCE_REINSTALL=true
      shift
      ;;
    --smoke-test)
      RUN_SMOKE_TEST=true
      shift
      ;;
    --no-shell)
      NO_SHELL=true
      shift
      ;;
    --branch)
      if [[ $# -lt 2 ]]; then
        echo "Error: --branch requires a value." >&2
        exit 2
      fi
      BRANCH="$2"
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

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: required command not found: ${command_name}" >&2
    exit 1
  fi
}

require_command git
require_command micromamba
require_command sha256sum
require_command awk

mkdir -p "${STATE_DIR}" "${MPLCONFIGDIR}" "$(dirname "${REPO_DIR}")"

BEFORE_COMMIT=""
if [[ -d "${REPO_DIR}/.git" ]]; then
  BEFORE_COMMIT="$(git -C "${REPO_DIR}" rev-parse HEAD 2>/dev/null || true)"
fi

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Cloning ai-research-env (${BRANCH}) into ${REPO_DIR} ..."
  git clone \
    --branch "${BRANCH}" \
    --single-branch \
    "${REPO_URL}" \
    "${REPO_DIR}"
else
  if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
    echo "Error: ${REPO_DIR} has local changes." >&2
    echo "Commit, stash, or remove them before updating the EFabric environment." >&2
    exit 1
  fi

  echo "Updating ai-research-env from origin/${BRANCH} ..."
  git -C "${REPO_DIR}" fetch --prune origin "${BRANCH}"

  if [[ "$(git -C "${REPO_DIR}" branch --show-current)" != "${BRANCH}" ]]; then
    git -C "${REPO_DIR}" checkout "${BRANCH}"
  fi

  git -C "${REPO_DIR}" merge --ff-only "origin/${BRANCH}"
fi

CURRENT_COMMIT="$(git -C "${REPO_DIR}" rev-parse HEAD)"
echo "ai-research-env commit: ${CURRENT_COMMIT}"

# If the repository changed, restart with the just-pulled version of this script
# so updates to bootstrap logic take effect immediately.
if [[ "${REEXECUTED}" != "1" ]] && \
   [[ -f "${REPO_DIR}/scripts/bootstrap-efabric-gpu.sh" ]] && \
   [[ "${BEFORE_COMMIT}" != "${CURRENT_COMMIT}" ]]; then
  exec env \
    AI_RESEARCH_ENV_BOOTSTRAP_REEXEC=1 \
    AI_RESEARCH_ENV_START_DIR="${START_DIR}" \
    bash "${REPO_DIR}/scripts/bootstrap-efabric-gpu.sh" "${ORIGINAL_ARGS[@]}"
fi

LOCK_FILE="${REPO_DIR}/conda-lock-gpu.yml"
if [[ ! -f "${LOCK_FILE}" ]]; then
  echo "Error: GPU lockfile not found: ${LOCK_FILE}" >&2
  exit 1
fi

LOCK_HASH="$(sha256sum "${LOCK_FILE}" | awk '{print $1}')"
LOCK_MARKER="${STATE_DIR}/conda-lock-gpu.sha256"
ENV_PREFIX="${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}"
ENV_PYTHON="${ENV_PREFIX}/bin/python"

NEEDS_INSTALL=false
if [[ "${FORCE_REINSTALL}" == true ]]; then
  NEEDS_INSTALL=true
elif [[ ! -x "${ENV_PYTHON}" ]]; then
  NEEDS_INSTALL=true
elif [[ ! -f "${LOCK_MARKER}" ]]; then
  NEEDS_INSTALL=true
elif [[ "$(cat "${LOCK_MARKER}")" != "${LOCK_HASH}" ]]; then
  NEEDS_INSTALL=true
fi

if [[ "${NEEDS_INSTALL}" == true ]]; then
  echo "GPU environment is missing or out of date."
  echo "Canonical lock SHA256: ${LOCK_HASH}"

  LOCK_VERSION="$(
    micromamba run -n "${LOCK_TOOLS_ENV}" conda-lock --version 2>/dev/null || true
  )"

  if [[ "${LOCK_VERSION}" != *"3.0.4"* ]]; then
    if [[ -d "${MAMBA_ROOT_PREFIX}/envs/${LOCK_TOOLS_ENV}" ]]; then
      echo "Updating ${LOCK_TOOLS_ENV} ..."
      micromamba install \
        -y \
        -n "${LOCK_TOOLS_ENV}" \
        -c conda-forge \
        python=3.12 \
        conda-lock=3.0.4
    else
      echo "Creating ${LOCK_TOOLS_ENV} ..."
      micromamba create \
        -y \
        -n "${LOCK_TOOLS_ENV}" \
        -c conda-forge \
        python=3.12 \
        conda-lock=3.0.4
    fi
  fi

  if [[ -d "${ENV_PREFIX}" ]]; then
    echo "Removing the previous ${ENV_NAME} before applying the new lock ..."
    micromamba remove -y -n "${ENV_NAME}" --all
  fi

  echo "Installing ${ENV_NAME} from the canonical GPU lock ..."
  micromamba run -n "${LOCK_TOOLS_ENV}" \
    conda-lock install \
    --conda "$(command -v micromamba)" \
    --name "${ENV_NAME}" \
    "${LOCK_FILE}"

  echo "Checking installed Python dependencies ..."
  micromamba run -n "${ENV_NAME}" python -m pip check

  printf '%s\n' "${LOCK_HASH}" > "${LOCK_MARKER}"
  echo "GPU environment now matches conda-lock-gpu.yml."
else
  echo "GPU environment already matches the latest canonical lock."
fi

printf '%s\n' "${CURRENT_COMMIT}" > "${STATE_DIR}/repo-commit"

if [[ "${RUN_SMOKE_TEST}" == true ]]; then
  echo "Running general environment smoke test ..."
  micromamba run -n "${ENV_NAME}" \
    python "${REPO_DIR}/scripts/smoke_test.py"

  echo "Running real-GPU smoke test ..."
  micromamba run -n "${ENV_NAME}" \
    python "${REPO_DIR}/scripts/gpu_smoke_test.py" --require-cuda
fi

echo
echo "EFabric GPU environment ready."
echo "Repository:  ${REPO_DIR}"
echo "Commit:      ${CURRENT_COMMIT}"
echo "Lock SHA256: ${LOCK_HASH}"
echo "Environment: ${ENV_NAME}"

if [[ "${NO_SHELL}" == true ]]; then
  exit 0
fi

if [[ -d "${START_DIR}" ]]; then
  cd "${START_DIR}"
else
  cd "${HOME}"
fi

export AI_RESEARCH_ENV_COMMIT="${CURRENT_COMMIT}"
export AI_RESEARCH_ENV_LOCK_SHA256="${LOCK_HASH}"

# Activate in this process, then replace it with the user's interactive Bash
# shell. No shell startup file is modified.
eval "$(micromamba shell hook --shell bash)"
micromamba activate "${ENV_NAME}"

echo
echo "Starting interactive Bash with ${ENV_NAME} activated."
exec bash -i
