#!/usr/bin/env bash

set -Eeuo pipefail

# Configure runtime defaults that belong to the canonical GPU environment but
# are not dependency specifications. micromamba >=2.5 persists environment
# variables in the target environment, so these settings follow the environment
# across interactive activation, `micromamba run`, EFabric, and Docker.

ENV_NAME="${1:-${AI_RESEARCH_ENV_GPU_ENV_NAME:-ai-research-env-gpu}}"

if ! command -v micromamba >/dev/null 2>&1; then
  echo "Error: micromamba is required to configure ${ENV_NAME}." >&2
  exit 1
fi

echo "Configuring PyTorch-first Transformers defaults for ${ENV_NAME} ..."
micromamba env config vars set \
  -n "${ENV_NAME}" \
  USE_TORCH=1 \
  USE_TF=0

micromamba run -n "${ENV_NAME}" python - <<'PY'
import os

expected = {
    "USE_TORCH": "1",
    "USE_TF": "0",
}

for name, value in expected.items():
    actual = os.environ.get(name)
    if actual != value:
        raise RuntimeError(
            f"Expected {name}={value!r} in configured GPU environment, "
            f"found {actual!r}."
        )

print("GPU runtime defaults configured: USE_TORCH=1, USE_TF=0")
PY
