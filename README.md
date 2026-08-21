# ai-research-env

Cross-platform, reproducible Python environment for AI, machine learning, and data science work.

The goal of this repository is to provide a general-purpose research environment that can be used consistently across local machines, remote compute environments, Docker, and NVIDIA GPU systems.

The repository uses:

- `environment.yml` as the human-edited portable environment specification
- `conda-lock.yml` as the deterministic multi-platform portable lockfile
- `environment-gpu.yml` and `conda-lock-gpu.yml` for the Linux x86-64 CUDA environment
- GitHub Actions to validate the environment across supported platforms
- Docker to provide portable prebuilt CPU and GPU environments
- GitHub Container Registry (GHCR) to distribute Docker images

The portable workflow is:

```text
environment.yml
      │
      ▼
conda-lock.yml
      │
      ├── native installation
      │     ├── Linux x86-64
      │     ├── Linux ARM64
      │     ├── macOS Intel
      │     ├── macOS Apple Silicon
      │     └── Windows x86-64
      │
      └── Docker
            ├── linux/amd64
            └── linux/arm64
```

The GPU workflow is deliberately separate so CUDA-specific constraints do not reduce portability of the default environment:

```text
environment-gpu.yml
      │
      ▼
conda-lock-gpu.yml
      │
      ├── native Linux x86-64 GPU installation
      ├── EFabric GPU Workspace
      └── Docker GPU image
            └── linux/amd64
```

For most users, the Docker image is the simplest way to use the environment. Native installation from the lockfiles is available when direct access to the environment is preferable.

## GPU support

A dedicated CUDA-enabled environment is maintained for Linux x86-64 systems with NVIDIA GPUs.

Current GPU target:

- Python 3.12
- PyTorch 2.5.1
- torchvision 0.20.1
- torchaudio 2.5.1
- CUDA runtime 12.4 through `pytorch-cuda=12.4`
- Transformers 4.48.3
- Hugging Face Accelerate
- BF16-capable PyTorch workloads
- PyTorch scaled dot-product attention
- the same general scientific, MEDS, Jupyter, and development tooling as the portable environment

The moving GPU Docker tag is:

```text
ghcr.io/eotles/ai-research-env:gpu
```

Immutable GPU tags use:

```text
ghcr.io/eotles/ai-research-env:gpu-sha-<commit>
```

For reproducible research runs, prefer an immutable tag/digest or record the exact environment commit and lock hash.

Run the GPU Docker image on a host with the NVIDIA Container Toolkit:

```bash
docker run -it --rm \
  --gpus all \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:gpu \
  zsh
```

Real GPU qualification is performed with:

```bash
python /opt/ai-research-env/gpu_smoke_test.py --require-cuda
```

That test exercises CUDA visibility, BF16 matrix multiplication, scaled dot-product attention, and a small Transformers forward pass on the GPU.

The PyTorch 2.5.1 / CUDA 12.4 stack has been qualified on an NVIDIA RTX A5000 on EFabric. See [`docs/gpu.md`](docs/gpu.md) for the detailed GPU design and qualification model.

## EFabric GPU workflow

EFabric provides its own `gpu-base` Workflow Image and persistent home storage. The supported integration therefore installs the canonical `conda-lock-gpu.yml` environment natively into persistent EFabric storage instead of maintaining a second EFabric-specific dependency specification.

Create a GPU Workspace using EFabric's `gpu-base`, SSH into it, then run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh)
```

That is the normal EFabric entry point. The launcher is fetched fresh from `main` every time you explicitly invoke it. It does not modify `~/.bashrc` and does not run automatically at login.

Internally, the launcher:

1. Maintains a persistent checkout under `$HOME/src/ai-research-env`.
2. Fast-forwards that checkout to the latest `origin/main`.
3. Computes the SHA256 of `conda-lock-gpu.yml`.
4. Reuses the existing persistent GPU environment when the lock is unchanged.
5. Recreates `ai-research-env-gpu` exactly from the canonical lock when it changes.
6. Runs `pip check` after an install or update.
7. Starts an interactive Bash shell with `ai-research-env-gpu` activated.
8. Prints the exact repository commit and lock SHA256 used.

The launched shell displays the environment name in the prompt and reports the resolved Python executable, making it clear that commands are running inside `ai-research-env-gpu`.

To force a clean reinstall:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --force-reinstall
```

To rerun both the general environment smoke test and the real GPU qualification before entering the shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --smoke-test
```

See [`docs/gpu.md`](docs/gpu.md) for EFabric implementation details, provenance guidance, and manual installation instructions.

## Repository contents

### `environment.yml`

The primary human-edited portable environment specification.

This file defines:

- package dependencies
- version constraints
- conda channels
- pip-installed dependencies
- supported platforms

The environment name is:

```text
ai-research-env
```

Normally, dependency changes should be made in `environment.yml`, not directly in `conda-lock.yml`.

### `conda-lock.yml`

The canonical generated portable lockfile.

It contains exact package versions and package hashes for all supported platforms:

- `linux-64`
- `linux-aarch64`
- `osx-64`
- `osx-arm64`
- `win-64`

The same `conda-lock.yml` file is used on every supported platform. `conda-lock` selects the appropriate platform-specific packages during installation.

Do not edit this file manually.

### `environment-gpu.yml` and `conda-lock-gpu.yml`

The GPU specification and canonical GPU lockfile are separate from the portable environment.

The GPU environment currently targets `linux-64` with PyTorch 2.5.1 and CUDA 12.4. Changes belong in `environment-gpu.yml`; do not edit `conda-lock-gpu.yml` manually.

### `Dockerfile` and `Dockerfile.gpu`

`Dockerfile` builds the portable CPU image from `conda-lock.yml`.

`Dockerfile.gpu` builds the Linux x86-64 CUDA image from `conda-lock-gpu.yml`.

The images contain the complete corresponding environments, including conda and PyPI dependencies.

The default container command starts JupyterLab on port `8888`.

### `scripts/generate-lockfile.sh`

Generates the canonical multi-platform `conda-lock.yml` from `environment.yml`.

The CI workflows use this script so that lockfile generation is implemented in one place.

### `scripts/generate-gpu-lockfile.sh`

Generates the canonical Linux GPU lockfile from `environment-gpu.yml`.

### `scripts/smoke_test.py`

Performs runtime validation of the installed environment.

The smoke test verifies important package imports, command-line tools, and representative computations from the AI and scientific Python stack.

The same smoke test is used by native environment validation and Docker image workflows.

### `scripts/gpu_smoke_test.py`

Performs CUDA-aware qualification of the GPU environment. In real-hardware mode it requires a visible CUDA device and exercises BF16, scaled dot-product attention, and Transformers on the GPU.

### `scripts/bootstrap-efabric-gpu.sh`

Provides the explicit one-command EFabric workflow described above. It updates the canonical checkout and persistent GPU environment only when the user invokes it.

### `.github/workflows/lockfile-check.yml`

Checks whether the current environment specification can be successfully resolved into a candidate lockfile.

This workflow runs:

- on relevant pull requests
- manually through `workflow_dispatch`

It does not modify the repository.

### `.github/workflows/lockfile-update.yml`

Maintains the canonical `conda-lock.yml`.

It runs:

- when relevant environment-definition files change on `main`
- weekly as a dependency-resolution and lockfile-drift check
- manually through `workflow_dispatch`

When run after an environment change:

1. A fresh candidate lockfile is generated.
2. The candidate is compared with the committed `conda-lock.yml`.
3. If the lockfile changed, the new canonical lockfile is committed automatically.
4. The Docker image workflow is then dispatched.

Scheduled runs report dependency-resolution failures or lockfile drift but do not commit changes.

Manual runs can optionally commit a changed lockfile.

### `.github/workflows/environment-install-check.yml`

Performs full installation and runtime validation of the environment.

The workflow:

1. Generates a fresh candidate lockfile.
2. Installs the complete locked environment.
3. Runs `pip check`.
4. Runs the repository smoke test.

The environment is tested on:

- Linux x86-64
- Linux ARM64
- macOS Intel
- macOS Apple Silicon
- Windows x86-64

This workflow runs on relevant pull requests, relevant pushes to `main`, on a periodic schedule, and manually.

### `.github/workflows/docker-image.yml`

Builds and tests the portable Docker image.

Before publication, the image is independently built and tested on:

- `linux/amd64`
- `linux/arm64`

Each architecture must pass:

- image build
- `pip check`
- the environment smoke test
- JupyterLab validation

After both architectures pass, a multi-architecture image can be published to GHCR.

### GPU workflows

The GPU environment has separate lock, install, and Docker workflows so CUDA-specific constraints remain isolated from the portable five-platform environment. GitHub CI validates the CUDA-enabled software build without requiring physical GPU hardware; real hardware is qualified separately with `gpu_smoke_test.py --require-cuda`.

### `.github/workflows/workflow-lint.yml`

Validates the repository's CI/CD code.

It checks:

- GitHub Actions workflows with `actionlint`
- shell scripts with `shellcheck`
- Python script syntax

### `.github/dependabot.yml`

Configures automated dependency update pull requests for GitHub Actions and Docker base images.

## Use the portable Docker image

A prebuilt multi-architecture Docker image is published to GitHub Container Registry:

```text
ghcr.io/eotles/ai-research-env:latest
```

Docker automatically selects the appropriate image architecture for supported systems.

### Pull the image

```bash
docker pull ghcr.io/eotles/ai-research-env:latest
```

### Start JupyterLab

Mount a local working directory into `/work`:

```bash
docker run -it --rm \
  -p 8888:8888 \
  -v /path/to/your/workspace:/work \
  ghcr.io/eotles/ai-research-env:latest
```

For example, to use the current directory:

```bash
docker run -it --rm \
  -p 8888:8888 \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:latest
```

The container starts JupyterLab by default.

Open the URL printed in the terminal. It will look similar to:

```text
http://127.0.0.1:8888/lab?token=...
```

Stop the container with `Ctrl+C`.

### Run a Python script

The default JupyterLab command can be overridden:

```bash
docker run --rm \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:latest \
  python your_script.py
```

### Open a shell

```bash
docker run -it --rm \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:latest \
  zsh
```

### Verify the image

Check installed Python package consistency:

```bash
docker run --rm \
  ghcr.io/eotles/ai-research-env:latest \
  python -m pip check
```

Run the full environment smoke test:

```bash
docker run --rm \
  ghcr.io/eotles/ai-research-env:latest \
  python /opt/ai-research-env/smoke_test.py
```

## Use the portable lockfile directly

For a native environment without Docker, install from the canonical:

```text
conda-lock.yml
```

The same lockfile is used for every supported platform. `conda-lock` automatically selects the packages for the current platform.

Supported platforms are:

| System | conda-lock platform |
|---|---|
| Linux x86-64 | `linux-64` |
| Linux ARM64 | `linux-aarch64` |
| macOS Intel | `osx-64` |
| macOS Apple Silicon | `osx-arm64` |
| Windows x86-64 | `win-64` |

### Clone the repository

```bash
git clone https://github.com/eotles/ai-research-env.git
cd ai-research-env
```

You need a conda-compatible package manager and `conda-lock`.

## Linux

The same commands apply to both x86-64 and ARM64 Linux systems.

Install `conda-lock`:

```bash
conda install -y \
  -n base \
  -c conda-forge \
  "conda-lock=3.*"
```

Install the locked environment:

```bash
conda-lock install \
  --name ai-research-env \
  conda-lock.yml
```

Activate it:

```bash
conda activate ai-research-env
```

Start JupyterLab:

```bash
jupyter lab
```

## macOS

The same commands apply to both Intel Macs and Apple Silicon Macs.

Install `conda-lock`:

```bash
conda install -y \
  -n base \
  -c conda-forge \
  "conda-lock=3.*"
```

Install the locked environment:

```bash
conda-lock install \
  --name ai-research-env \
  conda-lock.yml
```

Activate it:

```bash
conda activate ai-research-env
```

Start JupyterLab:

```bash
jupyter lab
```

## Windows

From Anaconda Prompt or another shell with conda available:

```powershell
conda install -y `
  -n base `
  -c conda-forge `
  "conda-lock=3.*"
```

Install the locked environment:

```powershell
conda-lock install `
  --name ai-research-env `
  conda-lock.yml
```

Activate it:

```powershell
conda activate ai-research-env
```

Start JupyterLab:

```powershell
jupyter lab
```

## Install with micromamba

The repository also supports micromamba.

Install `conda-lock` into the base environment:

```bash
micromamba install -y \
  -n base \
  -c conda-forge \
  "conda-lock=3.*"
```

Install the locked environment using micromamba as the conda-compatible installer:

```bash
micromamba run -n base \
  conda-lock install \
  --conda "$(command -v micromamba)" \
  --name ai-research-env \
  conda-lock.yml
```

Activate the environment:

```bash
micromamba activate ai-research-env
```

## Updating dependencies

The normal portable dependency update workflow starts with `environment.yml`. GPU dependency changes start with `environment-gpu.yml` and are handled by the corresponding GPU lock/install/Docker workflows.

### Standard portable update

1. Edit `environment.yml`.
2. Commit and push the change to `main`.
3. `lockfile-update` generates a fresh candidate lockfile.
4. If the resolved environment changed, the workflow updates and commits `conda-lock.yml`.
5. A changed canonical lockfile triggers the Docker image workflow.
6. Docker images are built and tested for both `linux/amd64` and `linux/arm64`.
7. After both image tests pass, the multi-architecture image is published to GHCR.

At the same time, `environment-install-check` validates that the complete environment can be installed and executed across all five supported native platforms.

### Pull request validation

For proposed environment changes, lockfile checks verify candidate resolution, environment-install checks install and test the environment, Docker workflows validate images, and `workflow-lint` validates workflows and scripts when relevant.

### Manual and scheduled checks

The lockfile and Docker workflows support manual runs. Periodic workflows also perform fresh dependency solves and environment installation checks to detect resolution failures or lockfile drift.

## Notes

- `environment.yml` and `conda-lock.yml` define the portable environment.
- `environment-gpu.yml` and `conda-lock-gpu.yml` define the CUDA-enabled Linux x86-64 environment.
- Do not edit generated lockfiles manually.
- `ghcr.io/eotles/ai-research-env:latest` is the portable Docker image.
- `ghcr.io/eotles/ai-research-env:gpu` is the moving GPU Docker image.
- The EFabric launcher is explicit and user-invoked; it does not alter shell startup behavior.
- Portable Docker images are validated on `linux/amd64` and `linux/arm64` before publication.
- Native portable environments are validated on Linux x86-64, Linux ARM64, Intel macOS, Apple Silicon, and Windows.
- Real GPU qualification is separate from GitHub CI and should be run on actual NVIDIA hardware.
