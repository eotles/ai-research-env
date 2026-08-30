# EFabric CPU workflow

Use the canonical portable `ai-research-env` environment on an EFabric CPU Workspace with:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh)
```

The launcher is explicit and does not modify shell startup files. Each invocation updates the persistent repository checkout, reconciles the persistent `ai-research-env` micromamba environment against the Linux x86-64 packages in `conda-lock.yml`, and starts an interactive Bash shell with the environment activated.

The normal environment location is under `$HOME/.micromamba`, so it persists with the EFabric Workspace home directory rather than using a read-only system prefix such as `/opt/conda`.

## Options

Force a clean reinstall:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh) \
  --force-reinstall
```

Run the general environment smoke test before entering the shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh) \
  --smoke-test
```

Reconcile the environment without starting an interactive shell:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh) \
  --no-shell
```

Test a non-default repository branch:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/main/scripts/bootstrap-efabric-cpu.sh) \
  --branch my-branch
```

For branch testing before a change is merged, fetch the launcher itself from that branch and pass the same branch to the bootstrap:

```bash
AI_RESEARCH_ENV_BRANCH=chatgpt/efabric-cpu-bootstrap \
  bash <(curl -fsSL https://raw.githubusercontent.com/eotles/ai-research-env/chatgpt/efabric-cpu-bootstrap/scripts/bootstrap-efabric-cpu.sh)
```

## Reconciliation behavior

The launcher records the SHA256 of `conda-lock.yml` under `$HOME/.ai-research-env`. If the installed environment exists and the lock hash is unchanged, it skips dependency installation.

When reconciliation is required, it first attempts the repository's incremental exact-lock reconciliation. If that fails, it removes and recreates `ai-research-env` from the canonical lock. A clean install is also used when the environment does not yet exist or `--force-reinstall` is supplied.

After installation, `python -m pip check` validates Python package consistency. `--smoke-test` additionally runs `scripts/smoke_test.py`.

The launcher prints the repository commit, lock SHA256, environment name, and bootstrap time so research runs can record the exact environment provenance.
