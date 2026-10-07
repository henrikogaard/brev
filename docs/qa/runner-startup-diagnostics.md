# Runner startup diagnostics

Run the manual **Runner startup diagnostics** workflow on `main` to compare
`macos-15` without an environment, `macos-15` with `release`, and `macos-26`
with `release`. All three jobs run independently. The workflow does not check
out code, reference secrets, sign artifacts, or publish releases. Its token
has no requested permissions.

The workflow also compares plain Ubuntu with Ubuntu using the selected
environment. Its `environment` dispatch input defaults to `release`; a fresh
name lets you isolate environment-specific state without copying secrets or
changing release protections. GitHub creates an empty environment for a new
name. Use a unique diagnostic name and preserve it with the evidence until
cleanup is authorized.

After the workflow has been merged:

```sh
gh workflow run runner-diagnostics.yml --ref main
gh run list --workflow runner-diagnostics.yml --limit 1
```

To compare a fresh environment on a diagnostic branch that contains this
workflow (the workflow must already exist on the default branch):

```sh
gh workflow run runner-diagnostics.yml --ref chore/runner-environment-diagnostics \
  -f environment=runner-diagnostic-2026-10-07
```

Select `release` only on `main` or an allowed tag; a diagnostic branch would
otherwise measure branch-policy rejection rather than runner startup.

Each started job records runner, image, OS, architecture, and selected Xcode
information in its log and job summary. It reports the default Xcode without
changing it. These checks prove startup and toolchain availability only.

If a job fails before producing logs, inspect its check annotations:

```sh
gh api repos/henrikogaard/brev/actions/runs/RUN_ID/jobs \
  --jq '.jobs[] | {id, name, conclusion, runner_name, check_run_url}'
gh api repos/henrikogaard/brev/check-runs/JOB_ID/annotations \
  --jq '.[] | {annotation_level, message}'
```

Compare results before changing the nightly workflow:

- If both `macos-15` jobs fail while `macos-26` starts, investigate the
  macOS 15 runner pool.
- If the plain job starts while both `release` jobs fail, investigate the
  environment-associated startup path and its annotations.
- If all three start, the minimal setup works. This does not prove the full
  nightly job can start or that the original failure was transient.
- Mixed results require a repeat before attributing a cause to either variable.
- If a fresh environment starts while `release` fails, the failure is specific
  to the existing environment's configuration or internal state.
- If fresh and release environments fail on both Ubuntu and macOS while plain
  jobs start, investigate GitHub's repository environment/job startup path.
- If Ubuntu environment jobs start while macOS environment jobs fail,
  investigate the macOS environment/job startup path.

The release environment permits `main` and `v*` tags. A feature-branch or PR
run would not reproduce the nightly's branch access. Keep that policy intact.
A new manual workflow must be present on the default branch before dispatch.
