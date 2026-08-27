# vLLM companion runtime

The canonical `ai-research-env-gpu` environment is optimized for reproducible
training, evaluation, and general GPU research. vLLM is maintained as a separate
companion runtime because its published wheels are tightly coupled to their own
PyTorch/CUDA binary stack.

This separation prevents installing vLLM from silently replacing the PyTorch and
CUDA packages qualified for `ai-research-env-gpu`.

## Canonical versions

The supported runtime versions are defined in:

```text
vllm-runtime.env
```

The current target is vLLM 0.28.0 with Python 3.12. The bootstrap also uses a
pinned, repository-managed `uv` binary so EFabric does not need to provide `uv`
as part of its base image.

## Supported NVIDIA GPUs

The EFabric companion runtime is not tied to an A100. It targets NVIDIA CUDA GPUs
supported by the pinned vLLM release. Current vLLM CUDA requirements specify
compute capability 7.5 or newer.

Examples that satisfy this requirement include:

- NVIDIA A100, compute capability 8.0
- NVIDIA RTX A5000, compute capability 8.6
- NVIDIA T4, compute capability 7.5
- newer Ampere, Ada, Hopper, and Blackwell devices that meet the same requirement

The bootstrap uses `uv pip install --torch-backend=auto`, so the PyTorch wheel
selection is based on the host NVIDIA driver rather than a hard-coded GPU model.
Actual usable model size and throughput will still depend on GPU memory and
hardware performance. An RTX A5000 has substantially less memory than many A100
configurations, so a model that runs on both GPUs may require different batching,
context length, or memory-utilization settings.

## EFabric

The supported one-command entry point is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-vllm.sh)
```

The bootstrap:

1. Updates the persistent `ai-research-env` checkout.
2. Reads the canonical vLLM, Python, and `uv` versions from `vllm-runtime.env`.
3. Installs the pinned `uv` binary into persistent user storage if it is absent.
   It does not modify shell startup files or depend on a system-wide `uv` install.
4. Creates an isolated persistent virtual environment at
   `$HOME/.venvs/ai-research-env-vllm`.
5. Installs vLLM with `uv pip install --torch-backend=auto`, allowing vLLM to
   select the PyTorch/CUDA wheel stack appropriate for the host NVIDIA driver.
6. Runs `pip check` and a lightweight vLLM import/runtime smoke test.
7. Reuses the environment on future invocations until the canonical vLLM
   specification changes.
8. Starts an interactive shell with the vLLM virtual environment first on
   `PATH`.

To require a supported real CUDA device during validation:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-vllm.sh) \
  --smoke-test
```

To additionally load a model and perform a real vLLM generation:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-vllm.sh) \
  --model facebook/opt-125m
```

Use `--force-reinstall` to recreate the companion environment and `--no-shell`
to reconcile it without launching an interactive shell.

## Container image

The dedicated image is built from the official vLLM OpenAI-compatible image and
published separately from the general GPU image.

Moving tag:

```text
ghcr.io/eotles/ai-research-env:vllm
```

Versioned tag:

```text
ghcr.io/eotles/ai-research-env:vllm-0.28.0
```

Immutable commit tags use:

```text
ghcr.io/eotles/ai-research-env:vllm-sha-<commit>
```

The upstream `vllm serve` entrypoint is preserved. The project image adds Git,
OpenSSH, jq, GNU time, and Zsh plus the repository vLLM smoke test.

Example:

```bash
docker run --rm --gpus all --ipc=host \
  -p 8000:8000 \
  ghcr.io/eotles/ai-research-env:vllm \
  --model Qwen/Qwen3-0.6B
```

## Qualification

Software-only CI verifies that the image imports the pinned vLLM release,
passes `pip check`, and contains the expected terminal tooling. Real GPU
qualification should additionally run:

```bash
python scripts/vllm_smoke_test.py --require-cuda --model facebook/opt-125m
```

The model-backed test is intentionally performed on real GPU infrastructure
rather than GitHub-hosted CPU runners.
