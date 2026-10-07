# Release environment startup evidence — 2026-10-07

## Finding

The failure follows the existing `release` environment. GitHub rejects or
fails acquisition before a runner starts, even for a Linux job with no
checkout, secret references, or release commands. Fresh environment jobs start
on Linux and macOS. The underlying internal failure is not exposed by the API;
this evidence does not prove whether environment rule evaluation or secret
provisioning is responsible.

## Observations

| Run / job | Ref / environment | Result |
| --- | --- | --- |
| [Release 37601107240](https://github.com/henrikogaard/brev/actions/runs/37601107240), `stable` | `v0.2.0` / `release` | Failed acquisition; runner ID 0, zero steps. Same result in run 37600850221. |
| [Build 37598773959](https://github.com/henrikogaard/brev/actions/runs/37598773959) | `main`, SHA `fef22759df90066498d50ce89d2a79d19e1a826c` | All 19 jobs passed using `macos-15`, including the macOS build. |
| [Diagnostics 37613181185](https://github.com/henrikogaard/brev/actions/runs/37613181185), `macos-15-plain` | `main` / none | Passed; runner ID 1000023080. |
| Diagnostics 37613181185, `macos-26-release` | `main` / `release` | Failed acquisition; runner ID 0, zero steps. |
| Diagnostics 37613181185, `macos-15-release` | `main` / `release` | Waiting at inspection; pending deployment lists zero wait timer and no reviewers. |
| [Diagnostics 37613417608](https://github.com/henrikogaard/brev/actions/runs/37613417608), `ubuntu-release` | `main`, SHA `1dce257386c64f6f251b9b7ba1737a48ef8ca4f8` / `release` | Failed acquisition; runner ID 0, zero steps. |
| Diagnostics 37613417608, `ubuntu-probe-environment` | `main` / empty `runner-probe` | Passed; runner ID 1000023091. |
| Diagnostics 37613417608, `macos-15-probe-environment` | `main` / empty `runner-probe` | Passed; runner ID 1000023096. |
| Diagnostics 37613417608, `macos-15-release` and `macos-26-release` | `main` / `release` | Both failed acquisition; runner ID 0, zero steps. |
| [Diagnostics 37613566767](https://github.com/henrikogaard/brev/actions/runs/37613566767), `ubuntu-environment` | `chore/runner-environment-diagnostics` / fresh restricted `runner-diagnostic-2026-10-07` | Passed; runner ID 1000023098. Its custom branch policy explicitly permits this branch. |
| Diagnostics 37613566767, `macos-26-release` | Same diagnostic branch / fresh restricted environment | Passed; runner ID 1000023101. The job ID retains the original release name, but its environment input selects the fresh environment. |
| Diagnostics 37613566767, `macos-15-release` | Same diagnostic branch / fresh restricted environment | Passed; runner ID 1000023109. All five jobs in this restricted-environment comparison passed. |

The release acquisition annotation reads:

> The job was not started because it repeatedly failed to be acquired (5 attempts).

The feature-branch run 37613287517 also passes fresh-environment probes, but
its `release` jobs are branch-policy rejections. Do not classify those as
acquisition failures or use them as an allowed-ref release comparison.

## Configuration verified through the GitHub API

- Repository is public, default branch `main`; Actions enabled.
- `release` allows branch `main` and tags `v*`.
- Only a branch policy is configured: no reviewer gate, wait timer, or custom
  deployment protection rule was returned.
- Expected signing/OAuth secret names are present. Values were neither read nor
  copied, and validity remains unverified.
- The fresh restricted environment has no secrets and uses the same custom
  branch-policy mechanism. Its successful Linux job rules out a blanket failure
  of restricted environments.
- The ARM64 capacity notice cannot explain the Linux release failure.

## Secret-update and onset checks

The current environment-secret metadata does not show an edit near the onset.
Developer ID material, provisioning profiles, App Store Connect material,
Sparkle signing key, and OAuth secrets were last updated on September 17.
The only later environment secrets are `BREV_GOOGLE_API_KEY` and
`BREV_GOOGLE_APP_ID`, created September 29, after acquisition failures were
already occurring. This does not rule out deleted secrets or internal GitHub
state changes; it does not support attributing the onset to a recorded edit of
the current signing secrets.

Nightly workflow-level success must be distinguished from build success:

- Run [35933998396](https://github.com/henrikogaard/brev/actions/runs/35933998396),
  created September 24 at 01:31 Oslo time, completed its build successfully
  with 18 steps and an assigned runner.
- Run [36073145304](https://github.com/henrikogaard/brev/actions/runs/36073145304),
  created September 25 at 01:31 Oslo time, reports workflow success but its
  build was skipped. It does not prove signing or release startup that night.
- Run [36201321338](https://github.com/henrikogaard/brev/actions/runs/36201321338),
  created September 26 at 01:31 Oslo time, has a failed build with zero steps
  and runner ID 0; the following night's run has the same signature.

## GitHub Support draft

Subject: Existing Actions environment causes runner acquisition failure on both Ubuntu and macOS

In public repository `henrikogaard/brev`, jobs using the existing `release`
environment fail before assignment with runner ID 0 and zero steps. The check
annotation reports repeated acquisition failure after five attempts.

This reproduces on allowed `main` and `v0.2.0` refs. Minimal diagnostic jobs
have no checkout, no secret references, no requested token permissions, and no
build, signing, or publishing commands. A Linux release-environment job also
fails, while Linux and macOS jobs in a fresh empty environment pass in the
same workflow run. A fresh environment with custom branch restrictions also
starts its Linux, macOS 15, and macOS 26 jobs successfully.

Please investigate the environment/job preparation path for environment ID
`22170646957` and check run `112765913314` in run `37613417608`. Release run
`37601107240`, check run `112725406861`, shows the same acquisition failure.
The existing environment permits `main` and `v*` tags and exposes no reviewer,
wait-timer, or custom protection rule through the API. We have preserved the
existing environment and its secrets for investigation.

## Remaining actions and limits

The report is prepared but has not been sent to Support. No release was rerun,
built, signed, notarized, published, or installed by this diagnostic session.
The current release environment and its secrets/protections remain unchanged.

If Support cannot repair the environment, a replacement release environment
with equivalent restrictions and re-entered signing secrets is a possible
recovery. That is a separate configuration change requiring maintainer
approval and subsequent startup, signing, notarization, and artifact checks.
Do not delete the existing environment as a diagnostic experiment.

The diagnostic branch and empty environment are retained with the evidence.
The main diagnostic's waiting macOS 15 release job is not counted as a failure
or pass. The later allowed-main comparison has final acquisition failures for
all three release jobs, and the restricted fresh-environment comparison is
fully successful.
