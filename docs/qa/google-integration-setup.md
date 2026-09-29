# Google integration configuration

Brev uses one Google Cloud project with platform-specific native OAuth clients.
Enable Gmail, Google Calendar, People, Google Tasks, Google Drive, and Google
Picker APIs in that project. API enablement, consent declarations, account
consent, and live feature verification are separate steps.

## Feature scopes

Keep existing mail scopes. Declare these scopes under Google Auth Platform →
Data Access. Brev requests them incrementally after a feature's explicit opt-in.

- `https://www.googleapis.com/auth/calendar.readonly`
- `https://www.googleapis.com/auth/calendar.events`
- `https://www.googleapis.com/auth/contacts.readonly`
- `https://www.googleapis.com/auth/contacts`
- `https://www.googleapis.com/auth/tasks.readonly`
- `https://www.googleapis.com/auth/tasks`
- `https://www.googleapis.com/auth/drive.file`

Declaring scopes does not update existing account grants. Use the source's
Re-authorize with Google action, enable editing when needed, and Refresh
Collections before testing writes. Branding verification is separate from
sensitive/restricted data-access verification.

## Drive build values

Create a dedicated API key in the OAuth clients' Cloud project. Restrict it to
Google Picker API and Google Drive API. The native picker hosts its page with
`https://drive.google.com` as its base URL; when applying website restrictions,
include `https://drive.google.com/*` and `https://docs.google.com/*`, then verify
that the actual WKWebView requests satisfy those restrictions on both platforms.
Do not broaden OAuth access beyond `drive.file` to repair a picker failure.

Set these values in the ignored `.env.local`, with file permissions `600`:

```dotenv
BREV_GOOGLE_API_KEY=<restricted-picker-api-key>
BREV_GOOGLE_APP_ID=<numeric-cloud-project-number>
```

The app ID is the Cloud project number, not the project ID or OAuth client ID.
Keep the existing platform-specific OAuth values. Use `BREV_ENV_FILE` to select
the canonical checkout's ignored configuration from an isolated worktree.
`script/build_and_run.sh --print-config` reports presence only. The local build
script loads these values and overrides stale generated settings. The API key
uses a protected temporary xcconfig rather than command-line arguments.

Add the same two names as GitHub Actions secrets in the `release` environment.
Both archive workflows pass them to `scripts/release-archive.sh`. Adding secrets
alone does not update an existing binary; rebuild after the wiring is merged.
For direct iOS xcodebuild invocations, provide the key through a temporary
mode-600 xcconfig and the project number as a build-setting override. The
Info.plist entries on both platforms expand the settings the app reads.

A separate build agent such as Devin needs its own protected environment values
if it builds this feature. GitHub Actions secrets are not inherited by agent
workspaces. Do not put values in prompts, knowledge files, logs, or tracked files.

## Verification

- Run `scripts/test-build-run-env.sh` and
  `scripts/test-developer-id-release-config.sh`.
- Build the test app and check that both bundle entries match the configured
  values without printing them. Never replace the daily-driver app for QA.
- Run Google Calendar/Contacts lifecycle and CRUD checks in the PIM parity
  matrix. Exercise Tasks separately when enabled.
- For #14, verify opt-in, file/folder picker, attach as bytes/link, Workspace
  export choice, save/upload, cancel, denial/revoke, offline, and source removal
  on macOS and iOS. Use disposable fixtures and redact evidence.
- Keep #11/#14 open until their acceptance evidence and maintainer acceptance
  are recorded; #3 depends on #11.

References: [Google Picker setup](https://developers.google.com/workspace/drive/picker/guides/web-picker),
[OAuth consent configuration](https://developers.google.com/workspace/guides/configure-oauth-consent),
[ADR-0072](../../ADRs/0072-provider-neutral-calendar-contact-authoring.md).
