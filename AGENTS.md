# Repository maintenance rules for coding agents

This repository is intended to be a stable, portable research environment. Reproducibility and validation guardrails take priority over making an individual pull request pass quickly.

## Non-negotiable guardrail rule

A failing CI check is evidence to diagnose, not an obstacle to bypass.

Do not weaken, remove, skip, replace, or route around an established validation check merely to make a change pass CI. If a validation rule appears incorrect, stop and explain the conflict. Any protocol change must be explicit, justified, and reviewed as a protocol change rather than hidden inside an unrelated dependency or feature change.

Do not create temporary write-enabled GitHub Actions workflows on feature branches to work around the normal repository process.

## Environment and lockfile pairs

The canonical source-of-truth pairs are:

- `environment.yml` -> `conda-lock.yml`
- `environment-gpu.yml` -> `conda-lock-gpu.yml`

Changes to an environment specification, or to its lockfile-generation script, require regeneration and commit of the corresponding canonical lockfile in the same pull request.

Use:

```bash
bash scripts/generate-lockfile.sh
bash scripts/generate-gpu-lockfile.sh
```

Do not edit generated lockfiles manually.

The post-merge `lockfile-update` and `gpu-lockfile-update` workflows are read-only safety and drift-monitoring mechanisms. They may resolve and upload candidate lockfiles, but they must never commit or push directly to `main`. Canonical lockfile changes belong on a branch and must pass the normal pull-request validation path.

## Required validation sequence

For environment changes:

1. Edit the human-maintained environment specification.
2. Regenerate the matching canonical lockfile on the same branch.
3. Commit both the source specification and generated lockfile.
4. Let the lock check independently re-resolve the environment and verify that the committed lock matches the candidate.
5. Let native install checks and Docker image checks run against the proposed repository state.
6. Diagnose any failure without weakening the check that found it.
7. Merge only after the intended required checks are green.

Portable lock solving is scoped to actual portable dependency inputs: `environment.yml`, `conda-lock.yml`, `scripts/generate-lockfile.sh`, and `scripts/compare_conda_locks.py`. A pull request that changes only CI or maintenance workflow code does not need a fresh five-platform dependency solve. Those workflow-only changes remain covered by the always-on `lint` workflow and repository protocol checks. This separation prevents unrelated upstream package-repository drift from blocking CI-maintenance changes without exempting dependency-changing pull requests from strict lock validation.

## Branch-level protection

The `lint` job in `.github/workflows/workflow-lint.yml` is intended to be the stable GitHub-required status check for `main`.

It must remain present on every pull request. Do not add pull-request path filtering to `workflow-lint.yml`, rename the `lint` job, or otherwise make that check conditional without treating the change as an explicit repository-protection change.

The heavier environment and Docker workflows are path-sensitive. When they are triggered, their failures must still be resolved before merge even though they are not globally required status checks in the GitHub ruleset.

See `docs/repository-protection.md` for the expected GitHub ruleset.

## CI and workflow permissions

Pull-request validation should be read-only. Workflows that also publish artifacts or images should grant write permissions only to the publishing job, and that job must not run for pull-request events.

The lock maintenance workflows are additionally required to remain repository-read-only because `main` is pull-request protected. They can report drift and upload candidate lock artifacts, but they cannot push canonical lock changes or dispatch publication based on an unreviewed generated lock.

New workflows must start read-only. If new write behavior is genuinely required, treat it as an explicit repository-protocol change and obtain repository-owner review.

## Protocol-critical files

Changes to these files deserve explicit review because they define or enforce repository guardrails:

- `AGENTS.md`
- `.github/CODEOWNERS`
- `.github/workflows/**`
- `scripts/check_repo_protocol.py`
- `scripts/compare_conda_locks.py`
- `environment.yml`
- `environment-gpu.yml`
- `conda-lock.yml`
- `conda-lock-gpu.yml`
- `Dockerfile*`
- `docs/repository-protection.md`

Read `README.md` for the current environment architecture, update workflow, and validation model before making maintenance changes.
