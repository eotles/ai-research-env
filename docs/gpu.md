# GPU / EFabric environment

The GPU target is intentionally separate from the portable CPU environment.

The portable image remains:

```text
ghcr.io/eotles/ai-research-env:latest
```

The GPU image is published as:

```text
ghcr.io/eotles/ai-research-env:gpu
```

Immutable GPU image tags use the form:

```text
ghcr.io/eotles/ai-research-env:gpu-sha-<commit>
```

For reproducible training runs, prefer an immutable tag or image digest over the moving `:gpu` tag.

## GPU software stack

The GPU environment is defined by `environment-gpu.yml` and locked independently in `conda-lock-gpu.yml`.

Current target:

- Linux x86-64 (`linux-64`)
- Python 3.12
- PyTorch 2.5.1
- torchvision 0.20.1
- torchaudio 2.5.1
- CUDA runtime 12.4 through `pytorch-cuda=12.4`
- XGBoost 3.4.1 with CUDA support
- Transformers 4.48.3
- the same general scientific, MEDS, Jupyter, Git, and Zsh tooling as the portable image

The image contains the CUDA runtime required by PyTorch. It does not include `nvcc` or a general-purpose CUDA compiler toolchain.

The GPU specification uses flexible channel priority because CUDA XGBoost needs
the compatible NCCL build from conda-forge. PyTorch and the CUDA 12.4 runtime
remain explicitly pinned to their established packages, and Arrow remains on
its CPU build because GPU Arrow is outside the qualification scope.

The host must provide a compatible NVIDIA driver and expose the GPU to the container runtime.

## Local Docker usage

A machine with the NVIDIA Container Toolkit can run the GPU image with:

```bash
docker run -it --rm \
  --gpus all \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:gpu \
  zsh
```

To start JupyterLab:

```bash
docker run -it --rm \
  --gpus all \
  -p 8888:8888 \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:gpu
```

## EFabric native GPU launcher

EFabric Workspaces provide their own GPU base image and persistent home storage. The tested integration path is to use EFabric's `gpu-base` Workflow Image and install the canonical `conda-lock-gpu.yml` environment into persistent home storage.

This keeps GitHub and `conda-lock-gpu.yml` as the source of truth while avoiding a second EFabric-specific dependency specification.

Nothing is added to `~/.bashrc`, and nothing runs automatically at login. Updating and entering the environment is always an explicit user action.

### Launch the latest environment

Create an EFabric GPU Workspace using the EFabric `gpu-base` Workflow Image, SSH into it, and run one command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh)
```

The launcher itself is fetched fresh from `main` on every invocation. There is no bootstrap script that the user needs to install, remember, or manually update on EFabric.

Internally, the launcher maintains a persistent checkout and micromamba environment under the EFabric home directory because the canonical lockfile and environment should survive Workspace replacement:

```text
$HOME/src/ai-research-env
$HOME/.micromamba
$HOME/.ai-research-env
$HOME/.cache/matplotlib
```

Those paths are implementation state rather than the user-facing launch interface. The normal entry point remains the single remote command above.

`MPLCONFIGDIR` is set explicitly because some EFabric Workspaces expose `$HOME/.config` as a non-writable file rather than a normal directory.

Each invocation:

1. Fetches the current launcher from GitHub before execution.
2. Fast-forwards the persistent `ai-research-env` checkout to the latest `origin/main`.
3. Records the exact Git commit being used.
4. Computes the SHA256 of `conda-lock-gpu.yml`.
5. Leaves the existing persistent GPU environment untouched when the lock is unchanged.
6. Recreates `ai-research-env-gpu` from the canonical lock when the lock changes.
7. Runs `pip check` after an install or update.
8. Starts an interactive Bash shell with `ai-research-env-gpu` activated.

This provides an explicit latest-version workflow without hidden login-time behavior. If the lock has not changed, the command should mostly be a quick Git update check before entering the existing environment.

Because the command intentionally executes the current `main` version of the launcher, it is appropriate for interactive development where "latest" behavior is desired. For a reproducible research run, record the commit and lock SHA256 printed by the launcher.

### Optional launcher modes

To force a clean reinstall from the current lock:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --force-reinstall
```

To rerun full hardware qualification before entering the shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --smoke-test
```

To update/reconcile the environment without launching an interactive shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --no-shell
```

The launcher prints the exact repository commit and lock SHA256. Inside the launched shell, the environment is already activated and regular commands can be used directly:

```bash
python your_script.py
jupyter lab
```

The launcher also exports:

```text
AI_RESEARCH_ENV_COMMIT
AI_RESEARCH_ENV_LOCK_SHA256
```

so the running shell retains the exact repository and lock provenance.

## GPU qualification

GitHub-hosted runners do not provide a CUDA GPU. CI therefore performs two levels of validation.

### Level 1: build-time / no-GPU validation

The normal GPU CI run verifies that:

- the Linux CUDA environment resolves and installs
- PyTorch is built with CUDA support
- `torch.version.cuda` reports CUDA 12.4
- XGBoost is built with CUDA support
- the general scientific environment passes its smoke tests
- Git, Zsh, and Jupyter terminal configuration work
- the GPU Docker image builds successfully

Run the static GPU check with:

```bash
python /opt/ai-research-env/gpu_smoke_test.py
```

### Level 2: real GPU validation

On EFabric or another GPU-backed host, run:

```bash
python scripts/gpu_smoke_test.py --require-cuda
```

This additionally requires and exercises:

- a visible CUDA device
- BF16 support
- BF16 matrix multiplication
- PyTorch scaled dot-product attention
- a small Hugging Face Transformers model forward pass on CUDA
- a small XGBoost training job on CUDA
- finite model outputs

The EFabric launcher's `--smoke-test` option runs both the general environment smoke test and this real-GPU qualification.

## Manual native installation

The GPU lock can also be installed directly on a Linux x86-64 host:

```bash
conda-lock install \
  --name ai-research-env-gpu \
  conda-lock-gpu.yml
```

Then activate it with the appropriate conda-compatible package manager.

## Updating the GPU environment

Human-edited GPU dependencies belong in `environment-gpu.yml`.

Generate the canonical lock with:

```bash
bash scripts/generate-gpu-lockfile.sh
```

Do not edit `conda-lock-gpu.yml` manually.

The GPU lock, native-install checks, Docker build, and real-hardware qualification are intentionally independent from the five-platform CPU environment. This prevents CUDA-specific constraints from reducing portability of the default environment.
