# Performance Diagnostics Runbook

Use this when Brev feels sluggish or when validating search/list/reader
performance before moving an issue to review.

## Privacy Rules

- Do not capture message bodies, subjects, sender/recipient addresses, raw search
  terms, message IDs, folder IDs, account IDs, credentials, tokens, or provider
  responses.
- Brev's local diagnostics use subsystem `eu.brevmail.brev` and category
  `Performance`.
- The diagnostics are local-only unified logs and Instruments signposts. They
  are not analytics, telemetry SDK events, or automatic uploads.

## Log Capture

Run this while exercising the app:

```sh
log stream --style compact --predicate 'subsystem == "eu.brevmail.brev" && category == "Performance"'
```

Record summarized values only:

- Operation name.
- Execution mode or path.
- Result count.
- Whether more pages exist.
- Sanitized error category, if any.
- Duration range.

## Signpost Capture

Open Instruments and use **Points of Interest** or **os_signpost** filtering for
subsystem `eu.brevmail.brev`.

Expected spans:

- `Message List Reload`
- `Message List Load More`
- `Message List Search`
- `Unified Inbox Reload`
- `Unified Inbox Load More`
- `Unified Inbox Search`
- `IMAP Messages Page`
- `IMAP Search`
- `IMAP Search Cache Read`
- `IMAP Body Fetch`
- `IMAP Message Source`
- `IMAP Body Cache Read`
- `Message Body Backend Fetch`
- `Body Render`
- `HTML Body Import`

## Standard Scenarios

1. Cold launch and first folder load.
2. Select a folder with a warm header cache.
3. Load the next message page.
4. Search current folder with the default cache-first/server-on-miss mode.
5. Search all mailboxes.
6. Search Unified Inbox across visible accounts.
7. Repeat a search that should be cache-warm.
8. Open a plain-text message.
9. Open an HTML message.
10. Open a message with attachments or inline CID images.

## Result Template

- Date/time:
- Build/commit:
- Device/macOS version:
- Provider aliases:
- Scenario:
- Cache state: cold / warm / reset
- Result count:
- Duration range:
- Dominant slow span:
- Error category:
- Private data omitted: yes

## Interpretation Guide

- Slow `ui.search` with fast `mail.search` points to UI/render/list state work.
- Slow `mail.search.cacheRead` points to local header-cache scanning.
- Slow `mail.search` with path `server` points to provider latency or IMAP query
  form behavior.
- Frequent `cacheFallback` means provider search is unreliable or unsupported
  for that query shape.
- Slow `mail.body.source` with path `cacheHit` points to local body-cache read or
  decode cost.
- Slow `mail.body.source` with path `server` points to IMAP body fetch latency.
- Slow `ui.body.render` or `ui.body.htmlImport` points to render/import cost
  after the body has already loaded.

## Performance Budgets

Warm-cache release budgets and the gate script are documented in
`docs/qa/performance-budgets.md`. Use `scripts/performance-budget-gate.sh`
after summarizing signpost timings into redacted JSON.
