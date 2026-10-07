# Runner startup diagnostics

Run the manual **Runner startup diagnostics** workflow on `main` to compare
`macos-15` without an environment, `macos-15` with `release`, and `macos-26`
with `release`. All three jobs run independently. The workflow does not check
out code, reference secrets, sign artifacts, or publish releases. Its token
has no requested permissions.

After the workflow has been merged:

```sh
gh workflow run runner-diagnostics.yml --ref main
gh run list --workflow runner-diagnostics.yml --limit 1
```

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

The release environment permits `main` and `v*` tags. A feature-branch or PR
run would not reproduce the nightly's branch access. Keep that policy intact.
A new manual workflow must be present on the default branch before dispatch.

## Environment isolation probes

The workflow also runs on pushes to `main` that change it, because the
maintainer PAT cannot dispatch workflows. Three extra jobs separate the
variables:

- `ubuntu-release`: the `release` environment on a Linux runner.
- `ubuntu-probe-environment` and `macos-15-probe-environment`: an empty
  `runner-probe` environment (auto-created, no secrets or rules).

If the probe environment starts on macOS while `release` fails everywhere,
the fault is in the `release` environment itself, not the runner pool.
