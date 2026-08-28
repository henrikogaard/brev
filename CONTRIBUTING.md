# Contributing to Brev

Thanks for helping improve Brev. The project accepts focused bug fixes,
accessibility improvements, tests, documentation, and features that match the
current provider and privacy decisions.

## Before changing code

1. Read `AGENTS.md` and `ADRs/README.md`.
2. Check existing issues and discussions before starting broad work.
3. Open an issue first when a change affects architecture, privacy, networking,
   account data, or distribution.

## Development workflow

1. Create a focused branch from current `main`.
2. Add or update a failing test before changing behavior when practical.
3. Keep views provider-neutral and use theme tokens instead of literal colors.
4. Never commit credentials, OAuth secrets, mailbox data, signing material, or
   private diagnostics.
5. Run the focused package tests plus:

   ```sh
   scripts/format.sh
   scripts/lint.sh
   scripts/privacy-audit.sh
   ```

6. Include rendered verification for UI changes and update `CHANGELOG.md` for
   user-visible behavior.

## Pull requests

Keep each pull request small enough to review. Describe the user-visible result,
tests run, skipped checks, privacy impact, and any ADR that governs the change.
Do not include generated credentials, live mailbox evidence, or unrelated
formatting.

By contributing, you agree that your contribution is licensed under the MIT
License in `LICENSE`.
