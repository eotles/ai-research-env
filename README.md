# ai-research-env

Cross-platform, reproducible Python environment for AI, machine learning, and data science work.

The repository is designed to provide the same research software base across local machines, remote compute environments, Docker, EFabric workspaces, and NVIDIA GPU systems. Human-edited environment specifications are resolved into committed canonical lockfiles, and CI validates the exact proposed repository state before changes are merged.

## Environment architecture

The portable environment is defined by:

```text
environment.yml
      |
      v
conda-lock.yml
      |
      +-- native installation
      |     +-- Linux x86-64
      |     +-- Linux ARM64
      |     +-- macOS Intel
      |     +-- macOS Apple Silicon
      |     +-- Windows x86-64
      |
      +-- Docker
            +-- linux/amd64
            +-- linux/arm64
```

The CUDA environment is deliberately separate so GPU constraints do not reduce portability of the default environment:

```text
environment-gpu.yml
      |
      v
conda-lock-gpu.yml
      |
      +-- native Linux x86-64 GPU installation
      +-- EFabric GPU workspace
      +-- Docker GPU image
```

The canonical source-of-truth pairs are:

- `environment.yml` and `conda-lock.yml`
- `environment-gpu.yml` and `conda-lock-gpu.yml`

The YAML environment files are human-maintained. The lockfiles are generated artifacts and must not be edited manually.

## Repository maintenance protocol

Reproducibility and validation guardrails take priority over making an individual pull request pass quickly.

**A failing CI check is evidence to diagnose, not an obstacle to bypass.** Do not weaken, skip, remove, or route around an established validation check merely to get a change through CI. If a repository protocol appears wrong, change it explicitly as a protocol change and review that change on its own merits.

Dependency-changing pull requests must include their corresponding canonical lockfile:

- changing `environment.yml` or `scripts/generate-lockfile.sh` requires a regenerated `conda-lock.yml`
- changing `environment-gpu.yml` or `scripts/generate-gpu-lockfile.sh` requires a regenerated `conda-lock-gpu.yml`

PR lock checks independently re-resolve the environment and verify that the committed canonical lock matches the candidate. Native install checks and Docker checks then validate the proposed repository state.

The post-merge `lockfile-update` and `gpu-lockfile-update` workflows remain useful as safety, drift-monitoring, and publication mechanisms. They are not substitutes for committing a matching lockfile in the dependency-changing PR.

Coding agents and automated maintainers must follow [`AGENTS.md`](AGENTS.md). Protocol-critical files are listed in [`.github/CODEOWNERS`](.github/CODEOWNERS), and pull requests include a repository-protocol checklist.

## Portable environment

The portable environment currently includes the scientific Python, ML, notebook, MEDS, development, and PyTorch CPU stack defined in `environment.yml`.

Supported lockfile platforms:

| System | conda-lock platform |
|---|---|
| Linux x86-64 | `linux-64` |
| Linux ARM64 | `linux-aarch64` |
| macOS Intel | `osx-64` |
| macOS Apple Silicon | `osx-arm64` |
| Windows x86-64 | `win-64` |

The moving portable Docker tag is:

```text
ghcr.io/eotles/ai-research-env:latest
```

For reproducible research runs, prefer an immutable image tag/digest or record the exact repository commit and lock SHA256.

### Run the portable Docker image

```bash
docker run -it --rm \
  -p 8888:8888 \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:latest
```

The default container command starts JupyterLab. To open a shell instead:

```bash
docker run -it --rm \
  -v "$PWD":/work \
  ghcr.io/eotles/ai-research-env:latest \
  zsh
```

Verify the image with:

```bash
docker run --rm \
  ghcr.io/eotles/ai-research-env:latest \
  python /opt/ai-research-env/smoke_test.py
```

## GPU environment

A dedicated CUDA-enabled environment is maintained for Linux x86-64 NVIDIA systems.

Current GPU target:

- Python 3.12
- PyTorch 2.5.1
- torchvision 0.20.1
- torchaudio 2.5.1
- CUDA runtime 12.4 through `pytorch-cuda=12.4`
- XGBoost 3.4.1 with CUDA support
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

Run the GPU image on a host with the NVIDIA Container Toolkit:

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

That test exercises CUDA visibility, BF16 matrix multiplication, scaled dot-product attention, a small Transformers forward pass, and XGBoost training on the GPU. The PyTorch 2.5.1 / CUDA 12.4 stack has been qualified on an NVIDIA RTX A5000 on EFabric.

See [`docs/gpu.md`](docs/gpu.md) for detailed GPU design, qualification, and manual installation guidance.

## vLLM companion runtime

vLLM is maintained as a separate companion runtime instead of being forced into the canonical CPU/GPU environments. This keeps the main environment stable while providing an optimized inference image when needed.

The moving vLLM Docker tag is:

```text
ghcr.io/eotles/ai-research-env:vllm
```

Versioned and commit-derived vLLM tags are also published by the vLLM Docker workflow.

See [`docs/vllm.md`](docs/vllm.md) for usage and design details.

## EFabric

### GPU workspace

Create a GPU workspace using EFabric's `gpu-base`, SSH into it, then run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh)
```

The launcher maintains a persistent checkout under `$HOME/src/ai-research-env`, fast-forwards it to the latest `origin/main`, and recreates `ai-research-env-gpu` only when the canonical GPU lock changes. It runs `pip check` after installation or update and prints the exact repository commit and lock SHA256 used.

Force a clean reinstall with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --force-reinstall
```

Run the environment and real GPU smoke tests before entering the shell with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-gpu.sh) \
  --smoke-test
```

### CPU workspace

The equivalent CPU-only EFabric bootstrap is:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh)
```

See [`docs/efabric-cpu.md`](docs/efabric-cpu.md) for the CPU workflow and [`docs/gpu.md`](docs/gpu.md) for the GPU workflow.

## Install from the portable lockfile

Clone the repository:

```bash
git clone https://github.com/eotles/ai-research-env.git
cd ai-research-env
```

Install `conda-lock` into a conda-compatible base environment:

```bash
conda install -y \
  -n base \
  -c conda-forge \
  "conda-lock=3.*"
```

Install the canonical portable environment:

```bash
conda-lock install \
  --name ai-research-env \
  conda-lock.yml
```

Then activate it:

```bash
conda activate ai-research-env
```

With micromamba:

```bash
micromamba install -y \
  -n base \
  -c conda-forge \
  "conda-lock=3.*"

micromamba run -n base \
  conda-lock install \
  --conda "$(command -v micromamba)" \
  --name ai-research-env \
  conda-lock.yml
```

## Updating dependencies

### Portable environment

Work on a branch and use this sequence:

1. Edit `environment.yml`.
2. Regenerate the canonical lockfile:

   ```bash
   bash scripts/generate-lockfile.sh
   ```

3. Commit both `environment.yml` and `conda-lock.yml`.
4. Open or update the pull request.
5. `lockfile-check` independently resolves a candidate lock and verifies that it matches the committed canonical lock.
6. `environment-install-check` installs and smoke-tests the complete environment across all five supported native platforms.
7. `docker-image` builds and tests the proposed portable image on `linux/amd64` and `linux/arm64`.
8. Merge only after the intended required checks are green.

### GPU environment

Use the same model:

1. Edit `environment-gpu.yml`.
2. Regenerate the canonical GPU lockfile:

   ```bash
   bash scripts/generate-gpu-lockfile.sh
   ```

3. Commit both `environment-gpu.yml` and `conda-lock-gpu.yml`.
4. `gpu-lockfile-check` independently resolves and compares the candidate lock.
5. `gpu-environment-install-check` validates installation and the CUDA-enabled software build.
6. `docker-image-gpu` builds and tests the proposed GPU image.
7. Run `gpu_smoke_test.py --require-cuda` on real hardware when hardware qualification is relevant.
8. Merge only after the intended required checks are green.

Generated lockfiles should never be hand-edited.

## CI and repository guardrails

### Lock checks

- `.github/workflows/lockfile-check.yml` resolves the portable specification and requires semantic equality with `conda-lock.yml`.
- `.github/workflows/gpu-lockfile-check.yml` resolves the GPU specification, validates the CUDA package target, and requires semantic equality with `conda-lock-gpu.yml`.
- `scripts/compare_conda_locks.py` ignores only non-semantic generation-path metadata when comparing locks.

### Install checks

- `environment-install-check` installs and validates Linux x86-64, Linux ARM64, Intel macOS, Apple Silicon, and Windows.
- `gpu-environment-install-check` validates the Linux CUDA software environment.
- `scripts/smoke_test.py` is shared by native and Docker validation.
- `scripts/gpu_smoke_test.py` provides CUDA-aware qualification.

### Docker checks

The CPU, GPU, and vLLM Docker workflows use read-only permissions during pull-request validation. Package write permission is granted only to publishing jobs, which do not run for pull-request events.

### Repository protocol check

`workflow-lint` runs on every pull request and provides the stable `lint` check intended for branch-level protection. It runs `scripts/check_repo_protocol.py`, which:

- requires environment or lock-generator changes to include the matching canonical lockfile
- requires both portable and GPU lock checks to retain strict candidate-versus-canonical validation
- verifies that the CPU and GPU Dockerfiles continue to consume canonical lockfiles
- prevents pull-request workflows from granting write permission at workflow scope
- rejects newly added write-enabled workflows
- runs alongside `actionlint`, `shellcheck`, and Python syntax checks

The heavier lock, install, and Docker workflows remain path-sensitive. When triggered, they must still be allowed to finish and should be green before merge. They should not be configured as global required checks unless their trigger model is changed so the check is present on every pull request.

## Repository contents

Key files:

- `environment.yml`: human-edited portable environment specification
- `conda-lock.yml`: generated canonical multi-platform portable lock
- `environment-gpu.yml`: human-edited Linux CUDA environment specification
- `conda-lock-gpu.yml`: generated canonical GPU lock
- `Dockerfile`: portable CPU image
- `Dockerfile.gpu`: GPU image
- `Dockerfile.vllm`: vLLM companion image
- `scripts/generate-lockfile.sh`: portable lock generator
- `scripts/generate-gpu-lockfile.sh`: GPU lock generator
- `scripts/compare_conda_locks.py`: semantic lock comparison helper
- `scripts/check_repo_protocol.py`: repository guardrail enforcement
- `scripts/smoke_test.py`: general runtime validation
- `scripts/gpu_smoke_test.py`: CUDA-aware validation
- `scripts/bootstrap-efabric-cpu.sh`: EFabric CPU bootstrap
- `scripts/bootstrap-efabric-gpu.sh`: EFabric GPU bootstrap
- `AGENTS.md`: coding-agent maintenance rules
- `.github/CODEOWNERS`: ownership for protocol-critical files
- `.github/pull_request_template.md`: protocol checklist for PRs
- `docs/efabric-cpu.md`: EFabric CPU documentation
- `docs/gpu.md`: GPU and EFabric GPU documentation
- `docs/vllm.md`: vLLM companion runtime documentation
- `docs/repository-protection.md`: exact GitHub `main` protection guidance

## Recommended GitHub repository settings

The repository files provide the guardrails, but GitHub should also enforce them at the branch level. For `main`, use an active branch ruleset that:

- prevents force pushes and deletion of `main`
- requires pull requests before merge
- requires the always-present GitHub Actions status check named `lint`
- requires branches to be up to date before merge
- requires conversation resolution before merge

The repository currently has one effective human reviewer. Do not require Code Owner approval until an independent reviewer is available, because the author cannot provide an independent approval for their own pull request. `.github/CODEOWNERS` should still be retained for ownership visibility.

The path-sensitive environment and Docker checks should not be configured as global required checks in the current design, because they do not run for unrelated pull requests. They remain mandatory by repository maintenance policy whenever they are triggered.

See [`docs/repository-protection.md`](docs/repository-protection.md) for the exact ruleset configuration and rationale.
