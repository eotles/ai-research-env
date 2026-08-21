#!/usr/bin/env bash

set -Eeuo pipefail

# Bootstrap the canonical ai-research-env GPU environment on EFabric.
#
# The script is intentionally idempotent:
#   1. Clone or fast-forward the repository to the requested branch.
#   2. Recreate ai-research-env-gpu only when conda-lock-gpu.yml changes.
#   3. Keep the micromamba environment in persistent EFabric home storage.
#   4. Optionally install a Bash login hook that runs once per Workspace boot.
#
# Typical first-time EFabric use:
#
#   bash scripts/bootstrap-efabric-gpu.sh --install-login-hook --smoke-test
#
# Future interactive Workspace boots can then update automatically through the
# installed ~/.bashrc hook. A manual invocation always checks for updates.

REPO_URL="${AI_RESEARCH_ENV_REPO_URL:-https://github.com/eotles/ai-research-env.git}"
REPO_DIR="${AI_RESEARCH_ENV_REPO_DIR:-${HOME}/src/ai-research-env}"
BRANCH="${AI_RESEARCH_ENV_BRANCH:-main}"
ENV_NAME="${AI_RESEARCH_ENV_GPU_ENV_NAME:-ai-research-env-gpu}"
LOCK_TOOLS_ENV="${AI_RESEARCH_ENV_LOCK_TOOLS_ENV_NAME:-ai-env-lock-tools}"
STATE_DIR="${AI_RESEARCH_ENV_STATE_DIR:-${HOME}/.ai-research-env}"

export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-${HOME}/.micromamba}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-${HOME}/.cache/matplotlib}"

LOGIN_MODE=false
INSTALL_LOGIN_HOOK=false
FORCE_REINSTALL=false
RUN_SMOKE_TEST=false
REEXECUTED="${AI_RESEARCH_ENV_BOOTSTRAP_REEXEC:-0}"

ORIGINAL_ARGS=("$@")

usage() {
  cat <<'EOF'
Usage: bootstrap-efabric-gpu.sh [options]

Bootstrap or update ai-research-env on an EFabric GPU Workspace.

Options:
  --install-login-hook  Add a ~/.bashrc hook that updates once per Workspace boot.
  --login               Internal lightweight mode used by the login hook.
  --force-reinstall     Reinstall the GPU environment even if the lock hash matches.
  --smoke-test          Run the general and real-GPU smoke tests after bootstrap.
  --branch NAME         Track a branch other than main.
  -h, --help            Show this help.

Environment overrides:
  AI_RESEARCH_ENV_REPO_URL
  AI_RESEARCH_ENV_REPO_DIR
  AI_RESEARCH_ENV_BRANCH
  AI_RESEARCH_ENV_GPU_ENV_NAME
  AI_RESEARCH_ENV_LOCK_TOOLS_ENV_NAME
  AI_RESEARCH_ENV_STATE_DIR
  MAMBA_ROOT_PREFIX
  MPLCONFIGDIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-login-hook)
      INSTALL_LOGIN_HOOK=true
      shift
      ;;
    --login)
      LOGIN_MODE=true
      shift
      ;;
    --force-reinstall)
      FORCE_REINSTALL=true
      shift
      ;;
    --smoke-test)
      RUN_SMOKE_TEST=true
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

workspace_session_id() {
  local pid1_start="unknown"

  if [[ -r /proc/1/stat ]]; then
    pid1_start="$(awk '{print $22}' /proc/1/stat 2>/dev/null || true)"
    pid1_start="${pid1_start:-unknown}"
  fi

  printf '%s:%s\n' "$(hostname)" "${pid1_start}"
}

write_login_hook() {
  local login_hook="${STATE_DIR}/efabric-login.sh"
  local bashrc="${HOME}/.bashrc"
  local begin_marker="# >>> ai-research-env EFabric bootstrap >>>"
  local end_marker="# <<< ai-research-env EFabric bootstrap <<<"

  mkdir -p "${STATE_DIR}" "${MPLCONFIGDIR}"

  cat > "${login_hook}" <<'EOF'
# Managed by ai-research-env/scripts/bootstrap-efabric-gpu.sh.
export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/.micromamba}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$HOME/.cache/matplotlib}"

_ai_research_env_repo="${AI_RESEARCH_ENV_REPO_DIR:-$HOME/src/ai-research-env}"
_ai_research_env_bootstrap="${_ai_research_env_repo}/scripts/bootstrap-efabric-gpu.sh"

if [[ -f "${_ai_research_env_bootstrap}" ]]; then
  bash "${_ai_research_env_bootstrap}" --login || \
    echo "Warning: ai-research-env EFabric bootstrap failed; continuing with the shell." >&2
fi

unset _ai_research_env_repo _ai_research_env_bootstrap
EOF

  touch "${bashrc}"

  if ! grep -Fq "${begin_marker}" "${bashrc}"; then
    cat >> "${bashrc}" <<EOF

${begin_marker}
if [[ -f "\$HOME/.ai-research-env/efabric-login.sh" ]]; then
  source "\$HOME/.ai-research-env/efabric-login.sh"
fi
${end_marker}
EOF
  fi

  echo "Installed EFabric login hook in ${bashrc}."
  echo "Future interactive Workspace sessions will check for updates once per Workspace boot."
}

require_command git
require_command micromamba
require_command sha256sum
require_command awk
require_command hostname

mkdir -p "${STATE_DIR}" "${MPLCONFIGDIR}" "$(dirname "${REPO_DIR}")"

SESSION_ID="$(workspace_session_id)"
SESSION_MARKER="${STATE_DIR}/last-workspace-session"

# The login hook should be nearly free after the first login in the same
# Workspace container. Manual invocations intentionally bypass this shortcut.
if [[ "${LOGIN_MODE}" == true && "${FORCE_REINSTALL}" == false ]]; then
  if [[ -f "${SESSION_MARKER}" ]] && \
     [[ "$(cat "${SESSION_MARKER}")" == "${SESSION_ID}" ]]; then
    exit 0
  fi
fi

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

# If the repository changed, restart using the just-pulled bootstrap script so
# changes to bootstrap logic take effect immediately. This also makes a remote
# bootstrap invocation converge onto the repository copy after cloning.
if [[ "${REEXECUTED}" != "1" ]] && \
   [[ -f "${REPO_DIR}/scripts/bootstrap-efabric-gpu.sh" ]] && \
   [[ "${BEFORE_COMMIT}" != "${CURRENT_COMMIT}" ]]; then
  exec env AI_RESEARCH_ENV_BOOTSTRAP_REEXEC=1 \
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

  # conda-lock installs through a `create` operation. Recreate the named
  # environment when the canonical lock changes rather than relying on an
  # in-place mutation, which keeps the resulting prefix exactly lock-derived.
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
printf '%s\n' "${SESSION_ID}" > "${SESSION_MARKER}"

if [[ "${INSTALL_LOGIN_HOOK}" == true ]]; then
  write_login_hook
fi

if [[ "${RUN_SMOKE_TEST}" == true ]]; then
  echo "Running general environment smoke test ..."
  micromamba run -n "${ENV_NAME}" \
    python "${REPO_DIR}/scripts/smoke_test.py"

  echo "Running real-GPU smoke test ..."
  micromamba run -n "${ENV_NAME}" \
    python "${REPO_DIR}/scripts/gpu_smoke_test.py" --require-cuda
fi

echo
echo "EFabric GPU bootstrap complete."
echo "Repository:  ${REPO_DIR}"
echo "Commit:      ${CURRENT_COMMIT}"
echo "Lock SHA256: ${LOCK_HASH}"
echo "Environment: ${ENV_NAME}"
echo
echo "Run a command with:"
echo "  micromamba run -n ${ENV_NAME} python your_script.py"
