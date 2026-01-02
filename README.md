# ai-research-env

Cross-platform, reproducible Python environment for AI and data science work.

This repo uses:
- `environment.yml` as the single human-edited dependency specification
- GitHub Actions + `conda-lock` to generate deterministic, platform-specific lockfiles
- GitHub Actions to build and publish a Docker image to GitHub Container Registry (GHCR)

The lockfiles are what you install from, they pin exact builds per platform.

## Repo contents

- `environment.yml`
  - The only file you normally edit.
  - The env name is set to `ai-research-env`.

- `locks/conda-*.lock`
  - Generated and committed.
  - One per target platform.
  - Produced by `conda-lock` using `--kind explicit`.

- `.github/workflows/*`
  - Automation that regenerates lockfiles when `environment.yml` changes.
  - Automation that builds/pushes a Docker image to GHCR when Linux lockfiles change.

- `Dockerfile`
  - Builds a Linux container environment from the Linux lockfiles.

## Use the Docker image

A prebuilt image is published to GHCR:

- `ghcr.io/eotles/ai-research-env:latest`

Pull it:

```bash
docker pull ghcr.io/eotles/ai-research-env:latest
```

Run it (starts JupyterLab by default, exposes port 8888, mounts a local folder into /work):
```bash
docker run -it --rm \
  -p 8888:8888 \
  -v /path/to/your/workspace:/work \
  -w /work \
  ghcr.io/eotles/ai-research-env:latest
```
Then open the URL printed in your terminal, it will look like:

```http://127.0.0.1:8888/lab?token=...```

Stop the server with ```Ctrl+C```.

Run a Python script instead of JupyterLab (override the default command):
```bash
docker run -it --rm \
  -v /path/to/your/workspace:/work \
  -w /work \
  ghcr.io/eotles/ai-research-env:latest \
  python your_script.py
```

## Use lockfiles directly (conda or micromamba)
If you want a native conda environment (no Docker), install from the lockfile for your platform.

### Windows (Anaconda/Miniconda)
Option A: install from a local file in this repo
```powershell
conda create -y -n ai-research-env --file locks/conda-win-64.lock
conda activate ai-research-env
jupyter lab
```

Option B: download the lockfile from GitHub, then install
This avoids cloning the repo.
```powershell
$LockUrl = "https://raw.githubusercontent.com/eotles/ai-research-env/main/locks/conda-win-64.lock"
$LockPath = "$env:TEMP\conda-win-64.lock"
Invoke-WebRequest -Uri $LockUrl -OutFile $LockPath

conda create -y -n ai-research-env --file $LockPath
conda activate ai-research-env
jupyter lab
```

### macOS (Intel or Apple Silicon)
If you have micromamba installed:

#### Option A: install from a local file in this repo
Apple Silicon:
```bash
micromamba create -y -n ai-research-env -f locks/conda-osx-arm64.lock
micromamba activate ai-research-env
jupyter lab
```

Intel:
```bash
micromamba create -y -n ai-research-env -f locks/conda-osx-64.lock
micromamba activate ai-research-env
jupyter lab
```

#### Option B: download the lockfile from GitHub, then install
Apple Silicon:
```bash
curl -L \
  -o /tmp/conda-osx-arm64.lock \
  https://raw.githubusercontent.com/eotles/ai-research-env/main/locks/conda-osx-arm64.lock

micromamba create -y -n ai-research-env -f /tmp/conda-osx-arm64.lock
micromamba activate ai-research-env
jupyter lab
```

Intel:
```bash
curl -L \
  -o /tmp/conda-osx-64.lock \
  https://raw.githubusercontent.com/eotles/ai-research-env/main/locks/conda-osx-64.lock

micromamba create -y -n ai-research-env -f /tmp/conda-osx-64.lock
micromamba activate ai-research-env
jupyter lab
```

## Linux (amd64 or arm64)

If you have micromamba installed:
### Option A: install from a local file in this repo
amd64:
```bash
micromamba create -y -n ai-research-env -f locks/conda-linux-64.lock
micromamba activate ai-research-env
jupyter lab --ip=0.0.0.0 --no-browser
```

arm64:
```bash
micromamba create -y -n ai-research-env -f locks/conda-linux-aarch64.lock
micromamba activate ai-research-env
jupyter lab --ip=0.0.0.0 --no-browser
```

Option B: download the lockfile from GitHub, then install
amd64:
```bash
curl -L \
  -o /tmp/conda-linux-64.lock \
  https://raw.githubusercontent.com/eotles/ai-research-env/main/locks/conda-linux-64.lock

micromamba create -y -n ai-research-env -f /tmp/conda-linux-64.lock
micromamba activate ai-research-env
jupyter lab --ip=0.0.0.0 --no-browser
```

arm64:
```bash
curl -L \
  -o /tmp/conda-linux-aarch64.lock \
  https://raw.githubusercontent.com/eotles/ai-research-env/main/locks/conda-linux-aarch64.lock

micromamba create -y -n ai-research-env -f /tmp/conda-linux-aarch64.lock
micromamba activate ai-research-env
jupyter lab --ip=0.0.0.0 --no-browser
```

Updating dependencies
1. Edit ```environment.yml```.
2. Commit and push to ```main```.
GitHub Actions will regenerate the lockfiles and commit them back.
A separate workflow builds and publishes the Docker image when the Linux lockfiles change.

Notes
- The Docker image is the easiest way to get a consistent environment on any machine with Docker.
- Installing from lockfiles is the most reproducible way to get a native conda environment.



