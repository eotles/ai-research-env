#!/usr/bin/env bash
set -Eeuo pipefail

# Build a CUDA-capable XGBoost companion runtime on top of the canonical EFabric
# GPU environment without mutating the locked conda environment. This mirrors the
# project's vLLM companion-runtime pattern: scientific/data dependencies remain
# available through system site packages while the companion wheel supplies a
# CUDA-enabled XGBoost backend.

ENV_NAME="${AI_RESEARCH_ENV_GPU_ENV_NAME:-ai-research-env-gpu}"
STATE_DIR="${AI_RESEARCH_ENV_STATE_DIR:-${HOME}/.ai-research-env}"
COMPANION_DIR="${AI_RESEARCH_ENV_XGBOOST_GPU_VENV:-${HOME}/.venvs/ai-research-env-xgboost-gpu}"
XGBOOST_VERSION="${AI_RESEARCH_ENV_XGBOOST_VERSION:-3.4.1}"

if [[ -n "${AI_RESEARCH_ENV_MAMBA_ROOT_PREFIX:-}" ]]; then
  export MAMBA_ROOT_PREFIX="${AI_RESEARCH_ENV_MAMBA_ROOT_PREFIX}"
elif [[ "${MAMBA_ROOT_PREFIX:-}" == "/opt/conda" ]] && [[ ! -w "/opt/conda" ]]; then
  export MAMBA_ROOT_PREFIX="${HOME}/.micromamba"
else
  export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-${HOME}/.micromamba}"
fi

BASE_PYTHON="${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}/bin/python"
if [[ ! -x "${BASE_PYTHON}" ]]; then
  echo "Error: ${ENV_NAME} does not exist. Run bootstrap-efabric-gpu.sh first." >&2
  exit 1
fi

mkdir -p "${STATE_DIR}" "$(dirname "${COMPANION_DIR}")"

if [[ ! -x "${COMPANION_DIR}/bin/python" ]]; then
  echo "Creating XGBoost GPU companion environment at ${COMPANION_DIR} ..."
  "${BASE_PYTHON}" -m venv --system-site-packages "${COMPANION_DIR}"
fi

"${COMPANION_DIR}/bin/python" -m pip install \
  --upgrade \
  --disable-pip-version-check \
  "xgboost==${XGBOOST_VERSION}"

"${COMPANION_DIR}/bin/python" - <<'PY'
import json
import xgboost as xgb

info = dict(xgb.build_info())
print("xgboost:", xgb.__version__)
print("build_info:", json.dumps(info, indent=2, sort_keys=True, default=str))
if not bool(info.get("USE_CUDA", False)):
    raise SystemExit("Installed XGBoost build does not report USE_CUDA=True")
PY

cat > "${STATE_DIR}/xgboost-cuda-companion.txt" <<EOF
installed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
base_environment=${ENV_NAME}
companion=${COMPANION_DIR}
xgboost=${XGBOOST_VERSION}
variant=cuda-wheel
EOF

echo
echo "CUDA XGBoost companion runtime ready."
echo "Base environment: ${ENV_NAME}"
echo "Companion:        ${COMPANION_DIR}"
echo "Python:           ${COMPANION_DIR}/bin/python"
echo "State:            ${STATE_DIR}/xgboost-cuda-companion.txt"
