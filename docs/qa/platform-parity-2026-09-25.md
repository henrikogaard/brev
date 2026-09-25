# Platform parity assessment — 2026-09-25

Post-merge pass over macOS and iOS on `main` @ `2435e40` (mock fixtures on
both: `Brev Test (2026-09-25).app`, BrevIOS on iPhone 17 / iOS 27.0). Both
apps were driven through the same flows against the same mock data.

## Verified equal (runtime-checked on both platforms)

| Surface | macOS | iOS | Verdict |
| --- | --- | --- | --- |
| Mailbox list | persistent sidebar; sections: Mailboxes ▸, Smart Views ▸, per-profile groups, PIM entries | Mailboxes drawer (drill-in): identical sections, icons, counts, disclosure chevrons | Parity |
| All Inboxes | 38 messages · 16 unread, tray.2 outline icon, same row layout | 38 messages · 16 unread, same fixtures, footer pill count | Parity |
| Message list rows | sender/subject/snippet/date + unread dot + thread count | identical row anatomy | Parity |
| Thread open | 3-column reader, unified thread card header, toolbar actions | push-in thread view, same card header, bottom action bar (reply / archive / trash / ⋯) | Parity |
| Search | scope chips (Local/Auto/Server/This folder/All), keyword chips, "Some results may be missing" caption | same chips + "Search finished" caption; result scoping identical | Parity |
| Sort / filter | `MailboxSortOrder` (shared, AppStorage-backed) + quick-filter UI | Sort By + Filter By menu over the same `MailboxSortOrder` | Parity |
| Message actions | shared `MessageCommandPresentation` (context menus, toolbar, reader ⋯) | same presentation (swipe actions, bottom bar, ⋯) | Parity |
| Compose | sheet; Apple-Mail-style chrome (circular send, pill cluster, muted quote, subject prefix collapse) | full-screen composer, same chrome + draft persistence + "Draft saved." toast | Parity |
| Drafts | tap reopens composer with fields intact | same | Parity |
| Smart views | same set; folder-scoped filtering (no leak into folders) | same set + same scoping | Parity |
| PIM entries (Calendar/Contacts/Tasks) | rail/pane + covers with real empty states | covers with real empty states + Done | Parity |
| Unread counts / badges | sidebar counts | drawer + row counts match | Parity |

## Platform-idiomatic differences (by design, not gaps)

| Area | macOS | iOS |
| --- | --- | --- |
| Invocation | menu bar, context menus, keyboard shortcuts + column keyboard focus (no visible ring — selection tint implies focus) | swipe actions (leading/trailing, full swipe), pull-to-refresh, bottom action bar, ⋯ overflow |
| Navigation | persistent NSSplitView sidebar + 3-column layout | drill-in Mailboxes drawer + push/pop |
| Compose | sheet window | full-screen |
| Selection model | pointer + keyboard (arrows/Return activate) | touch only |

## Remaining observations

| # | Observation | Severity | Note |
| --- | --- | --- | --- |
| P1 | `ui.body.visible` (first rich-HTML thread open, WKWebView) measured 1222 ms — over the 600 ms `cached_thread_open_ms` hard limit | medium | one sample; first WKWebView spawn per session. Re-measure warm on the live run; consider pre-warming the renderer |
| P2 | Only 1 of ~15 thread opens emitted `ui.body.visible` — `cancelMessageOpenTiming` cancels prior opens on rapid reselection | low | instrumentation expected-lossy, but a metric consumer could misread this as missing coverage |
| P3 | `mail.*` backend events (cache query, page fetch, startup restore) are IMAP-only — mock benchmark cannot cover `cached_inbox_query_ms` | low | expected; requires the live run in `docs/qa/performance-live-run.md` |
| P4 | iOS sim produced far fewer trace events than macOS for the same gestures (list reload + search logged; body opens not captured) | low | same cancel-on-reselect mechanism; also iOS reader may complete via `bodyState` before webView paint |

## Net

Feature parity is effectively reached on the user-visible surface: identical
fixtures, counts, row anatomy, search scoping, sort/filter, message actions,
compose chrome, drafts, and smart views all match. Differences left are
platform idioms (menus/keyboard vs swipe/touch navigation). The only
performance-relevant parity flag is the first-render WKWebView warmup (P1).
