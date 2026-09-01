# GitHub protection for `main`

Repository files enforce most of the maintenance protocol, but GitHub should also prevent accidental or automated direct changes to `main`.

## Current design

The always-present pull-request status check is the `lint` job from `.github/workflows/workflow-lint.yml`.

That workflow intentionally runs on every pull request and performs:

- repository protocol validation through `scripts/check_repo_protocol.py`
- GitHub Actions validation with `actionlint`
- shell validation with `shellcheck`
- Python syntax validation for repository scripts and configuration

Other environment checks remain path-sensitive because they are substantially more expensive. When relevant files change, the corresponding lock, install, and Docker workflows must still be allowed to finish and should be green before merge.

## Recommended ruleset

Create a branch ruleset targeting the default branch, `main`, with enforcement set to **Active**.

Recommended rules:

1. **Restrict deletions**: enabled.
2. **Block force pushes**: enabled.
3. **Require a pull request before merging**: enabled.
4. **Required approvals**: `0` for the current single-owner repository.
5. **Dismiss stale pull request approvals when new commits are pushed**: enable if independent reviewers are added later.
6. **Require review from Code Owners**: do not enable while the repository has only one effective reviewer. The author cannot satisfy an independent approval requirement on their own pull request. Keep `.github/CODEOWNERS` for ownership visibility and enable this rule once an independent reviewer is available.
7. **Require status checks to pass**: enabled.
8. Add the GitHub Actions check named **`lint`** as a required status check.
9. **Require branches to be up to date before merging**: recommended.
10. **Require conversation resolution before merging**: recommended.

Do not add the path-sensitive environment or Docker jobs as globally required status checks. A workflow skipped by path filtering may not produce the required check for an unrelated pull request, which can leave the pull request blocked. Those workflows remain required by repository maintenance policy whenever their trigger paths are relevant.

## Why `lint` is the branch-level gate

The `lint` check is deliberately lightweight enough to run for every pull request and broad enough to detect attempts to alter the repository maintenance protocol. In particular, `scripts/check_repo_protocol.py` checks source/lock pairing, lock-check structure, Docker lock consumption, and workflow permission invariants.

The heavier validation layers remain conditional:

- portable dependency changes: `lockfile-check`, `environment-install-check`, and `docker-image`
- GPU dependency changes: `gpu-lockfile-check`, `gpu-environment-install-check`, and `docker-image-gpu`
- vLLM runtime changes: `docker-image-vllm`

A green `lint` check is therefore necessary for merge, but it does not replace the relevant scientific and runtime validation workflows.

## GitHub UI path

In the repository:

1. Open **Settings**.
2. Open **Rules** -> **Rulesets**.
3. Choose **New ruleset** -> **New branch ruleset**.
4. Name it `Protect main`.
5. Set enforcement to **Active**.
6. Target the default branch, or include only `main`.
7. Apply the rules listed above.
8. Save the ruleset.

After saving, open a small test pull request and confirm that GitHub blocks merge until the `lint` check succeeds.

## Administrative note

GitHub rulesets are repository settings, not files in this repository. They are intentionally documented here so their expected configuration is versioned and reviewable even though GitHub stores the active rule outside Git.
