#!/usr/bin/env bash

set -Eeuo pipefail

# Bootstrap/update and enter the isolated vLLM companion runtime on EFabric.
# vLLM intentionally owns its own PyTorch/CUDA wheel stack instead of mutating
# the canonical ai-research-env-gpu conda environment.

REPO_URL="${AI_RESEARCH_ENV_REPO_URL:-https://github.com/eotles/ai-research-env.git}"
REPO_DIR="${AI_RESEARCH_ENV_REPO_DIR:-${HOME}/src/ai-research-env}"
BRANCH="${AI_RESEARCH_ENV_BRANCH:-main}"
VENV_DIR="${AI_RESEARCH_ENV_VLLM_VENV_DIR:-${HOME}/.venvs/ai-research-env-vllm}"
STATE_DIR="${AI_RESEARCH_ENV_STATE_DIR:-${HOME}/.ai-research-env}"
START_DIR="${AI_RESEARCH_ENV_START_DIR:-${PWD}}"
REEXECUTED="${AI_RESEARCH_ENV_VLLM_BOOTSTRAP_REEXEC:-0}"
BOOTSTRAP_START="${SECONDS}"

FORCE_REINSTALL=false
RUN_SMOKE_TEST=false
SMOKE_MODEL=""
NO_SHELL=false
ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Usage: bootstrap-efabric-vllm.sh [options]

Update ai-research-env, reconcile the isolated vLLM companion runtime, and
launch an interactive Bash shell using that runtime.

Options:
  --force-reinstall  Recreate the vLLM virtual environment.
  --smoke-test       Require a supported CUDA GPU and run the lightweight test.
  --model MODEL      Also load MODEL and perform a real vLLM generation.
  --no-shell         Update/reconcile the runtime, then exit.
  --branch NAME      Track a branch other than main.
  -h, --help         Show this help.

Environment overrides:
  AI_RESEARCH_ENV_REPO_URL
  AI_RESEARCH_ENV_REPO_DIR
  AI_RESEARCH_ENV_BRANCH
  AI_RESEARCH_ENV_VLLM_VENV_DIR
  AI_RESEARCH_ENV_STATE_DIR
  AI_RESEARCH_ENV_START_DIR
  AI_RESEARCH_ENV_VLLM_UV_DIR
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
    --model)
      if [[ $# -lt 2 ]]; then
        echo "Error: --model requires a value." >&2
        exit 2
      fi
      RUN_SMOKE_TEST=true
      SMOKE_MODEL="$2"
      shift 2
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
require_command sha256sum
require_command awk

mkdir -p "${STATE_DIR}" "$(dirname "${REPO_DIR}")" "$(dirname "${VENV_DIR}")"

BEFORE_COMMIT=""
if [[ -d "${REPO_DIR}/.git" ]]; then
  BEFORE_COMMIT="$(git -C "${REPO_DIR}" rev-parse HEAD 2>/dev/null || true)"
fi

if [[ "${REEXECUTED}" == "1" ]] && [[ -d "${REPO_DIR}/.git" ]]; then
  echo "Using the checkout updated by the bootstrap re-exec."
elif [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Cloning ai-research-env (${BRANCH}) into ${REPO_DIR} ..."
  git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${REPO_DIR}"
else
  if [[ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]]; then
    echo "Error: ${REPO_DIR} has local changes." >&2
    echo "Commit, stash, or remove them before updating the vLLM runtime." >&2
    exit 1
  fi

  echo "Updating ai-research-env from origin/${BRANCH} ..."
  git -C "${REPO_DIR}" fetch \
    --prune \
    origin \
    "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}"

  if [[ "$(git -C "${REPO_DIR}" branch --show-current)" != "${BRANCH}" ]]; then
    if git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/${BRANCH}"; then
      git -C "${REPO_DIR}" checkout "${BRANCH}"
    else
      git -C "${REPO_DIR}" checkout \
        --track \
        -b "${BRANCH}" \
        "origin/${BRANCH}"
    fi
  fi

  git -C "${REPO_DIR}" merge --ff-only "origin/${BRANCH}"
fi

CURRENT_COMMIT="$(git -C "${REPO_DIR}" rev-parse HEAD)"
echo "ai-research-env commit: ${CURRENT_COMMIT}"

if [[ "${REEXECUTED}" != "1" ]] && \
   [[ -f "${REPO_DIR}/scripts/bootstrap-efabric-vllm.sh" ]] && \
   [[ "${BEFORE_COMMIT}" != "${CURRENT_COMMIT}" ]]; then
  exec env \
    AI_RESEARCH_ENV_VLLM_BOOTSTRAP_REEXEC=1 \
    AI_RESEARCH_ENV_START_DIR="${START_DIR}" \
    bash "${REPO_DIR}/scripts/bootstrap-efabric-vllm.sh" "${ORIGINAL_ARGS[@]}"
fi

CONFIG_FILE="${REPO_DIR}/vllm-runtime.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Error: vLLM configuration not found: ${CONFIG_FILE}" >&2
  exit 1
fi

# CONFIG_FILE is intentionally dynamic because REPO_DIR is configurable.
# shellcheck disable=SC1090,SC1091
source "${CONFIG_FILE}"

: "${VLLM_VERSION:?VLLM_VERSION must be set in vllm-runtime.env}"
: "${VLLM_PYTHON:?VLLM_PYTHON must be set in vllm-runtime.env}"
: "${UV_VERSION:?UV_VERSION must be set in vllm-runtime.env}"

UV_BIN_DIR="${AI_RESEARCH_ENV_VLLM_UV_DIR:-${STATE_DIR}/vllm-tools}"
UV_BIN="${UV_BIN_DIR}/uv"

uv_semver() {
  "${UV_BIN}" --version 2>/dev/null | awk '{print $2}'
}

ensure_uv() {
  local actual_version=""
  local version_output=""

  if [[ -x "${UV_BIN}" ]]; then
    actual_version="$(uv_semver || true)"
  fi

  if [[ "${actual_version}" == "${UV_VERSION}" ]]; then
    echo "Using managed $("${UV_BIN}" --version)."
    return
  fi

  require_command curl
  mkdir -p "${UV_BIN_DIR}"

  echo "Installing managed uv ${UV_VERSION} into ${UV_BIN_DIR} ..."
  curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | \
    env UV_UNMANAGED_INSTALL="${UV_BIN_DIR}" sh

  if [[ ! -x "${UV_BIN}" ]]; then
    echo "Error: uv installer completed but ${UV_BIN} was not created." >&2
    exit 1
  fi

  actual_version="$(uv_semver)"
  if [[ "${actual_version}" != "${UV_VERSION}" ]]; then
    version_output="$("${UV_BIN}" --version 2>/dev/null || true)"
    echo "Error: expected uv ${UV_VERSION}, found ${version_output:-unknown}." >&2
    exit 1
  fi

  echo "Installed $("${UV_BIN}" --version)."
}

ensure_uv

SPEC_HASH="$(sha256sum "${CONFIG_FILE}" | awk '{print $1}')"
SPEC_MARKER="${STATE_DIR}/vllm-spec.sha256"
VENV_PYTHON="${VENV_DIR}/bin/python"

NEEDS_INSTALL=false
if [[ "${FORCE_REINSTALL}" == true ]]; then
  NEEDS_INSTALL=true
elif [[ ! -x "${VENV_PYTHON}" ]]; then
  NEEDS_INSTALL=true
elif [[ ! -f "${SPEC_MARKER}" ]]; then
  NEEDS_INSTALL=true
elif [[ "$(cat "${SPEC_MARKER}")" != "${SPEC_HASH}" ]]; then
  NEEDS_INSTALL=true
fi

if [[ "${NEEDS_INSTALL}" == true ]]; then
  INSTALL_START="${SECONDS}"
  echo "Installing isolated vLLM ${VLLM_VERSION} runtime ..."
  rm -rf "${VENV_DIR}"

  "${UV_BIN}" venv \
    --python "${VLLM_PYTHON}" \
    --seed \
    "${VENV_DIR}"

  "${UV_BIN}" pip install \
    --python "${VENV_PYTHON}" \
    --torch-backend=auto \
    "vllm==${VLLM_VERSION}"

  echo "Checking installed Python dependencies ..."
  "${VENV_PYTHON}" -m pip check

  AI_RESEARCH_ENV_VLLM_VERSION="${VLLM_VERSION}" \
    "${VENV_PYTHON}" "${REPO_DIR}/scripts/vllm_smoke_test.py"

  printf '%s\n' "${SPEC_HASH}" > "${SPEC_MARKER}"
  echo "vLLM companion runtime now matches vllm-runtime.env."
  echo "vLLM install time: $((SECONDS - INSTALL_START)) seconds"
else
  echo "vLLM companion runtime already matches vllm-runtime.env."
fi

if [[ "${RUN_SMOKE_TEST}" == true ]]; then
  smoke_args=(--require-cuda)
  if [[ -n "${SMOKE_MODEL}" ]]; then
    smoke_args+=(--model "${SMOKE_MODEL}")
  fi

  AI_RESEARCH_ENV_VLLM_VERSION="${VLLM_VERSION}" \
    "${VENV_PYTHON}" \
    "${REPO_DIR}/scripts/vllm_smoke_test.py" \
    "${smoke_args[@]}"
fi

printf '%s\n' "${CURRENT_COMMIT}" > "${STATE_DIR}/vllm-repo-commit"

echo
echo "EFabric vLLM companion runtime ready."
echo "Repository:   ${REPO_DIR}"
echo "Commit:       ${CURRENT_COMMIT}"
echo "vLLM:        ${VLLM_VERSION}"
echo "uv:          $("${UV_BIN}" --version)"
echo "Environment: ${VENV_DIR}"
echo "Bootstrap time: $((SECONDS - BOOTSTRAP_START)) seconds"

if [[ "${NO_SHELL}" == true ]]; then
  exit 0
fi

if [[ -d "${START_DIR}" ]]; then
  cd "${START_DIR}"
else
  cd "${HOME}"
fi

SHELL_RC="${STATE_DIR}/efabric-vllm-shell.bashrc"
cat > "${SHELL_RC}" <<EOF
if [[ -f "\${HOME}/.bashrc" ]]; then
  source "\${HOME}/.bashrc"
fi

unset CONDA_DEFAULT_ENV CONDA_PREFIX CONDA_PROMPT_MODIFIER
unset USE_TORCH USE_TF
export VIRTUAL_ENV="${VENV_DIR}"
export PATH="${VENV_DIR}/bin:\${PATH}"
export AI_RESEARCH_ENV_VLLM_VERSION="${VLLM_VERSION}"
export AI_RESEARCH_ENV_COMMIT="${CURRENT_COMMIT}"
PS1='(ai-research-env-vllm) \u@\h:\w\$ '

printf 'Activated ai-research-env-vllm\n'
printf 'vLLM: %s\n' "${VLLM_VERSION}"
printf 'Python: %s\n' "\$(command -v python)"
EOF

echo
echo "Starting interactive Bash with ai-research-env-vllm activated."
exec bash --rcfile "${SHELL_RC}" -i
