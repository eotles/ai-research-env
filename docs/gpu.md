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
python /opt/ai-research-env/gpu_smoke_test.py --require-cuda
```

This additionally requires and exercises:

- a visible CUDA device
- BF16 support
- BF16 matrix multiplication
- PyTorch scaled dot-product attention
- a small Hugging Face Transformers model forward pass on CUDA
- finite model outputs

This is the hardware qualification step for a newly published GPU image.

## Native installation

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
