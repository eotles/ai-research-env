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
- Transformers 4.48.3
- the same general scientific, MEDS, Jupyter, Git, and Zsh tooling as the portable image

The image contains the CUDA runtime required by PyTorch. It does not include `nvcc` or a general-purpose CUDA compiler toolchain.

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

## EFabric native GPU bootstrap

EFabric Workspaces currently provide their own GPU base image and persistent home storage. The tested integration path is therefore to use EFabric's `gpu-base` Workflow Image and install the canonical `conda-lock-gpu.yml` environment into persistent home storage.

This keeps GitHub and `conda-lock-gpu.yml` as the source of truth while avoiding a second EFabric-specific dependency specification.

### First-time setup

Create an EFabric GPU Workspace using the EFabric `gpu-base` Workflow Image, then SSH into it and run:

```bash
mkdir -p "$HOME/src"

git clone \
  https://github.com/eotles/ai-research-env.git \
  "$HOME/src/ai-research-env"

cd "$HOME/src/ai-research-env"

bash scripts/bootstrap-efabric-gpu.sh \
  --install-login-hook \
  --smoke-test
```

The bootstrap script uses persistent locations under your EFabric home directory:

```text
$HOME/src/ai-research-env
$HOME/.micromamba
$HOME/.ai-research-env
$HOME/.cache/matplotlib
```

It also sets `MPLCONFIGDIR` explicitly because some EFabric Workspaces expose `$HOME/.config` as a non-writable file rather than a normal directory.

### Automatic latest-on-boot behavior

`--install-login-hook` adds a small managed block to `~/.bashrc`.

On the first interactive login to each new Workspace container, the hook:

1. Fast-forwards the local `ai-research-env` checkout to the latest `origin/main`.
2. Records the exact Git commit being used.
3. Computes the SHA256 of `conda-lock-gpu.yml`.
4. Leaves the existing GPU environment untouched when the lock is unchanged.
5. Recreates `ai-research-env-gpu` from the new canonical lock when the lock changes.
6. Runs `pip check` after an environment install or update.

Additional shells in the same running Workspace skip the network/update work. A new Workspace boot triggers a fresh check.

This makes interactive EFabric development track the latest canonical environment without paying the cost of reinstalling it on every login.

To check for updates manually at any time:

```bash
bash "$HOME/src/ai-research-env/scripts/bootstrap-efabric-gpu.sh"
```

To force a clean reinstall from the current lock:

```bash
bash "$HOME/src/ai-research-env/scripts/bootstrap-efabric-gpu.sh" \
  --force-reinstall
```

To rerun full hardware qualification:

```bash
bash "$HOME/src/ai-research-env/scripts/bootstrap-efabric-gpu.sh" \
  --smoke-test
```

The bootstrap prints the exact repository commit and lock SHA256. Record those values for research runs where provenance matters. Automatic `main` tracking is convenient for interactive development, while a recorded commit and lock hash provide the reproducibility boundary for an experiment.

### Running commands

The environment can be used without shell activation:

```bash
export MAMBA_ROOT_PREFIX="$HOME/.micromamba"

micromamba run -n ai-research-env-gpu \
  python your_script.py
```

The login hook persists `MAMBA_ROOT_PREFIX` and `MPLCONFIGDIR` for interactive Bash sessions.

## GPU qualification

GitHub-hosted runners do not provide a CUDA GPU. CI therefore performs two levels of validation.

### Level 1: build-time / no-GPU validation

The normal GPU CI run verifies that:

- the Linux CUDA environment resolves and installs
- PyTorch is built with CUDA support
- `torch.version.cuda` reports CUDA 12.4
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
- finite model outputs

The EFabric bootstrap's `--smoke-test` option runs both the general environment smoke test and this real-GPU qualification.

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
