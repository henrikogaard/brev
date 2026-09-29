# Main @ 32fc5da — verification pass (2026-09-29)

Continuation QA on `main` @ `32fc5da` (lead referenced `ef56b60`; main moved forward, tree clean).
Rebuilt both targets from current main — iOS Debug-iphonesimulator (Xcode-27.0-RC, OAuth vars baked)
installed on iPhone 17 / iOS 27.0 (UDID `8E780854-5816-4435-AD8F-8098DF847EB5`); macOS `Brev Test
(2026-09-29).app` via `script/build_and_run.sh --mock`. `/Applications/Brev.app` untouched.

## Part A — #155: iPhone top status rail renders as an INSET CARD

Merged commit `319d465` passes `inset:` for all three rail cases (`.rootStatus`/`.offline` →
`BrevInlineStatus(inset:true)`; `authenticationRequired` → `ImportProgressBanner(inset:true)`).

| Case | Result | Evidence |
|------|--------|----------|
| `authenticationRequired` (`ImportProgressBanner`) | ✅ inset card | Pixel-proven: card spans x:24→1181 (8pt margins @3x, screen w=1206) with rounded-corner taper + top gap below floating nav chrome; NOT a flush band (flush = x:0→1205). "Sign in again" → reconnect sheet opens, prefilled, correctly titled **"Sign in again"** (not "Update mail password"). |
| `.rootStatus` (`BrevInlineStatus`) | ✅ inset card | Pixel-proven x:24→1181 + taper. Triggered via scoped `pfctl` block-return on Mailo IMAP IPs (instant RST → sync failure → "Sync needs attention" banner). pf fully flushed after. |
| `.offline` (`BrevInlineStatus`) | ⚠️ same-component verified | `.offline` itself is **untriggerable on this sim**: no Wi-Fi pane in Settings, no CommCenter/`mobilewifimanager` daemon, no sim network binaries, `simctl` has no network subcommand, CC airplane tile renders as illegible frosted tiles that dismiss on tap. `.offline` and `.rootStatus` share `BrevInlineStatus(inset:true)` — verified via `.rootStatus` + merged-diff code inspection. Never disable host networking (`ifconfig en0 down` = kills VM uplink + session). |

Recording: `brev-main-32fc5da-banners/brev-main-32fc5da-banners-edited.mp4`

## Part B — #99: macOS unified-inbox keyboard navigation

Verified on the macOS mock build (`Brev Test (2026-09-29).app`):

- ✅ Sidebar mailbox click → keyboard focus hands off into the message list
  (`messageListFocusRequestID++` on activation).
- ✅ Up/Down arrows move selection through the merged unified timeline.
- ✅ Expanded thread children interleave after their parent in displayed order; arrows walk
  parent → child1 → child2 → next parent (`keyboardNavigableSequence` splices children).
- ✅ Return toggles expansion on multi-message threads; Return on a draft opens composer;
  bulk-preservation not exercised.
- ✅ Auto-scroll follows selection; no wraparound.

Recording: `brev-main-32fc5da-mackbnav/brev-main-32fc5da-mackbnav-edited.mp4`

## Part C — #11 Google PIM legs on the real QA account

The Google OAuth write-scope grant **completed successfully**: "Allow editing" toggle →
ASWebAuthenticationSession → Henrik SMS challenge (code relayed, accepted) → unverified-app consent →
calendar write scope granted. "Allow editing" now ON for the Calendar source.

**#149 classification — VERIFIED (this is the correct behavior):** Triggering "Refresh Collections"
(collection discovery runs ONLY on explicit Settings action per ADR-0006, not via "Sync Now")
surfaced the real Google state:

| Source | Status | Meaning |
|--------|--------|---------|
| Google · Calendar | **Failed / `serviceDisabled`** | `calendarList.list` 403 → `accessNotConfigured`. **Google Calendar API is disabled in Brev's OAuth GCP project.** Banner shows exact remediation: "The Google API this source uses … is not enabled for Brev's sign-in project. Enable it in Google Cloud Console — reconnecting cannot fix this." |
| Google · Contacts | **Failed / `authenticationRequired`** | `contactGroups` 403 with a *non*-disabled-API reason → token lacks contacts scope. A full "Re-authorize with Google…" re-auth was completed (no SMS this time) but the source **still shows `authenticationRequired`** — the re-auth re-established the grant without adding contacts scope (consent showed only "already has access"). People API is also likely disabled/mis-scoped in GCP. |
| Google · Tasks | not enabled | "Enable Tasks" button; expected same wall. |

**→ Google Calendar & Contacts CRUD legs (create/edit/delete + web round-trip) are BLOCKED** —
Henrik-side config, not an app bug. Needs Google Calendar API + People API (+ Tasks API) enabled in
the GCP project for OAuth client `879180545678-56u4q10vret4fuq8p03k43qobaroui6f`. Escalated to lead.

**Capability-driven UI verified:** the Contacts cover correctly shows **no "+" create button** for the
unwritable/`authenticationRequired` source (`editing.canEdit` false) — "Showing cached data / No contacts".

### Dynamic Type pass (iOS, Larger Accessibility Sizes, slider ~73%)

- ✅ **Mail list:** renders cleanly — sender/subject/preview readable, correctly truncated with
  ellipsis, timestamps + section headers intact, search capsule fine. No clipping/overlap.
- ❌ **Message reader — DEFECT:** the "cached conversation" action chips ("Include Spam and Trash",
  "Load related mail") **overflow at 73%** — text breaks into cramped narrow columns with mid-word
  hyphenation ("Loa-d re-lat-ed mail", "In-clud-e Spa-m and Tra…"). Message body itself is fine;
  same buttons render cleanly at normal size. The chips don't accommodate large Dynamic Type.

Recording: `brev-main-32fc5da-pim/brev-main-32fc5da-pim-edited.mp4`

## Verified on device vs not reached

| Item | On device? | Note |
|------|-----------|------|
| #155 inset card — authRequired + rootStatus | ✅ | pixel-proven |
| #155 inset card — .offline | ⚠️ | same-component only; untriggerable on sim |
| #99 macOS keyboard nav | ✅ | mock build |
| #149 serviceDisabled + authRequired classification | ✅ | both surfaced correctly |
| Google write-scope OAuth | ✅ | SMS → consent → Allow editing ON |
| Google Calendar CRUD + round-trip | ❌ | BLOCKED: Calendar API disabled in GCP (serviceDisabled) |
| Google Contacts CRUD + round-trip | ❌ | BLOCKED: authenticationRequired persists after re-auth |
| Dynamic Type — mail list | ✅ | clean |
| Dynamic Type — reader | ✅ | DEFECT found (chips overflow) |
| Google Drive picker (#14) | ➖ | expected gap — no `BREV_GOOGLE_API_KEY`/`APP_ID` provisioned; skipped by design |

## Needs from Henrik

1. **GCP enablement** — in Google Cloud Console for the OAuth client project
   (`879180545678-…`), enable: Google Calendar API, People API, Tasks API. Then re-run the #11
   CRUD legs (calendar source will need re-auth after enablement).
2. **Reader Dynamic Type fix** — cached-conversation action chips need to accommodate large text
   (flexible sizing, not fixed-width columns).
