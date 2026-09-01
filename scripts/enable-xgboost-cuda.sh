#!/usr/bin/env bash
set -Eeuo pipefail

# Enable the CUDA-capable XGBoost variant inside the canonical EFabric GPU
# environment. This is an explicit companion step until the GPU lockfile itself
# is regenerated with the CUDA XGBoost variant.

ENV_NAME="${AI_RESEARCH_ENV_GPU_ENV_NAME:-ai-research-env-gpu}"
STATE_DIR="${AI_RESEARCH_ENV_STATE_DIR:-${HOME}/.ai-research-env}"

if [[ -n "${AI_RESEARCH_ENV_MAMBA_ROOT_PREFIX:-}" ]]; then
  export MAMBA_ROOT_PREFIX="${AI_RESEARCH_ENV_MAMBA_ROOT_PREFIX}"
elif [[ "${MAMBA_ROOT_PREFIX:-}" == "/opt/conda" ]] && [[ ! -w "/opt/conda" ]]; then
  export MAMBA_ROOT_PREFIX="${HOME}/.micromamba"
else
  export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-${HOME}/.micromamba}"
fi

command -v micromamba >/dev/null 2>&1 || {
  echo "Error: micromamba is required." >&2
  exit 1
}

if [[ ! -x "${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}/bin/python" ]]; then
  echo "Error: ${ENV_NAME} does not exist. Run bootstrap-efabric-gpu.sh first." >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"

echo "Installing CUDA-capable XGBoost into ${ENV_NAME} ..."
micromamba install \
  -y \
  -n "${ENV_NAME}" \
  -c conda-forge \
  'py-xgboost=3.4.1=*_cuda*'

"${MAMBA_ROOT_PREFIX}/envs/${ENV_NAME}/bin/python" - <<'PY'
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
environment=${ENV_NAME}
xgboost=3.4.1
variant=cuda
EOF

echo
echo "CUDA XGBoost companion runtime ready."
echo "Environment: ${ENV_NAME}"
echo "State:       ${STATE_DIR}/xgboost-cuda-companion.txt"
echo "Note: an exact GPU lock reconciliation may restore the CPU XGBoost variant; rerun this companion step until conda-lock-gpu.yml is regenerated for CUDA XGBoost."
