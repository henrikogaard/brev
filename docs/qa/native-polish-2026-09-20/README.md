# Native mail polish — 2026-09-20

Scope: #49 compose overflow, #51 reader stall, and desktop compose hierarchy.
Synthetic MockBackend mail only; no message sent and no live account changed.

## Runtime evidence

| Surface | Observed result |
| --- | --- |
| iPhone 18 Pro, iOS 27.0, standard size | Sample conversation body renders; collapse/re-expand and Back respond; Reply opens a compose sheet with the long synthetic recipient constrained to the viewport. |
| Compose, all 12 Dynamic Type categories | Runtime snapshots expose named Close, Send and More controls at every size. |
| Compose, largest accessibility size | Header fields scroll vertically with the toolbar retained. Empty compose closes back to the inbox. |
| macOS 27, 680-point compose window | Editing tools lead, delivery controls trail, and Send has a text label. Synthetic recipient, subject and body can be entered. Templates and AI remain in the secondary menu; security remains capability/configuration gated. |
| Desktop mailbox and Settings | Three-column mailbox and account settings inspected in the test app; no further layout defect reproduced in this pass. |

Screenshots: [loaded reader](reader-loaded.jpg), [reply compose](compose-reply.jpg),
[largest compose](compose-largest.jpg), [largest form after scroll](compose-scrolled.jpg), and
[plain-text fallback](reader-plain.jpg).
All addresses in these captures are synthetic `.example` fixtures.

## Diagnosis and verification

The frozen reader repeatedly received a newly allocated environment command
closure during SwiftUI layout. Disabling rich rendering and auto-scroll did not
remove the loop. Instrumentation isolated `readerCommandAction` invalidation;
removing that injection restored rendering. A stable, non-observable action
object now routes to the latest owner callback without changing environment
identity. Temporary instrumentation was removed.

The recipient flow layout measured children without a width proposal, allowing
an accessibility-sized placeholder or address to dictate the entire sheet width.
A hosting-controller regression failed before bounding measurement and passed
afterwards. Measurement and placement now use the same available-width limit.

- iOS: 9 focused tests in 3 suites pass (11 phone pixel cases, flow-width and
  command-owner regressions). The owner test verifies identity and latest callback.
- macOS: 6 focused tests in 3 suites pass (compose pixel reference, reader command
  handoff and compact reader retention).
- Both native Debug app builds pass. macOS uses the dated Brev Test identity.
- Lint, zero-change format, iOS baseline inventory and diff check pass.
- An initial broader macOS snapshot run found an existing `profileManager`
  reference mismatch on macOS 27. That unrelated reference was not rewritten.

## Limits / acceptance still required

Runtime checks used one simulator/runtime and one Mac. No physical-device,
spoken VoiceOver, another iOS runtime, real-provider or release validation was
performed. Runtime accessibility snapshots still include background mailbox
nodes; this pass does not establish correct VoiceOver focus isolation. The
sample reader was also checked with rich rendering disabled: it now preserves
the supplied plain-text paragraphs while attributed import is pending or fails.
A complete rich/plain live-provider content matrix remains for #51 acceptance. At large
text sizes, the embedded message editor typography needs its own accessibility
review. Issues remain open for maintainer QA.

Review follow-up: preserved the busy-state disable on the accessibility toolbar
and explicitly selected the desktop compose snapshot in the compatible-host CI
job. The fallback paragraph regression failed before the fix and passed after it.
Busy-state restoration reuses the existing header invariant; no new async send
fixture was added for this one-line modifier correction.
