# ai-research-env

Cross-platform, reproducible Python environment for AI and data science work.

This repo uses:
- `environment.yml` as the single human-edited dependency specification
- GitHub Actions + `conda-lock` to generate deterministic, platform-specific lockfiles

The lockfiles are what you actually install from, they pin exact builds per platform.

## Repo contents

- `environment.yml`
  - The only file you normally edit.
  - The env name is set to `ai-research-env`.

- `locks/conda-*.lock`
  - Generated and committed.
  - One per target platform.
  - These are produced by `conda-lock` using `--kind explicit`.

- `.github/workflows/*`
  - Automation that regenerates lockfiles when `environment.yml` changes.

- `Dockerfile` (optional, recommended if you want Docker on macOS)
  - Builds a Linux container environment from the Linux lockfile.

## Install and use

### Windows (Anaconda/Miniconda)

Create the environment from the Windows lockfile:

```powershell
conda create -y -n ai-research-env --file locks/conda-win-64.lock
conda activate ai-research-env
python -c "import numpy, pandas; print('ok')"
