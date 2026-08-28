# Mail context column — design

- **Date:** 2026-07-25
- **Status:** Shipped (macOS v1 in #308; scope/transparency follow-up in #309)
- **Related ADRs:** ADR-0002 (theme), ADR-0006 (privacy / network),
  ADR-0008 (AI Writer), ADR-0028 (invariants), ADR-0026 (supervised
  mailbox action agent), ADR-0027 (manual thread summary), ADR-0030
  (local sync/cache). Related issues: #303 (UI workbench), #305 (AI
  safety policy), #184 / Mailbox Assistant wiring gap.
- **Inspiration:** Product request for a right-hand column while browsing
  mail (sender context + mailbox chat). Not a port of Electron MailRovers.

## Goal

On macOS, let the user open an optional right-hand **Mail Context** column
while browsing email. The column has two stacked regions:

1. **Sender panel** — local-only facts about the selected message’s sender.
2. **Mailbox chat** — opt-in AI that can answer questions about mail and
   propose supervised mailbox actions (never mutate without explicit
   review and typed confirmation).

## Decisions locked in brainstorming

| Decision | Choice |
|---|---|
| Chat role | Both Q&A and supervised actions; mutations need explicit confirm |
| Sender panel | Local-only facts (no AI enrichment in v1) |
| Column open | Explicit toggle; default closed |
| Default chat scope | Current sender (visible scope chip) |
| Platforms | macOS only in v1; iOS/iPad later |
| Layout approach | Fourth inspector column (not detached window, not unified AI rail) |

## Non-goals (v1)

- iOS / iPhone / iPad sheet parity
- Auto-opening the column on message select
- Always-on settings preference as the primary open path
- AI-generated sender blurbs or CRM enrichment
- Autonomous agents, background triage, or AI that can send mail
- Semantic embedding index beyond existing local FTS/search
- Cross-account sender merge
- Editing Contacts / CardDAV write from this panel

## Current baseline

- macOS workspace is a three-column `NavigationSplitView` (sidebar, list,
  reader) with density/theme systems already in place.
- Compose **AI Writer** lives in the compose toolbar; thread **Summarize**
  lives in the conversation controls row.
- **Mailbox Assistant** (`MailboxActionAgentSheet`, planner, settings) exists
  under ADR-0026, but root presentation for `.mailboxAssistant` currently
  returns `EmptyView()` and nothing assigns that sheet — confirm UI must be
  wired through the new chat action path (or restored) as part of this work.
- Local search/index and optional `ContactLookupProviding` can feed sender
  facts without network.

## Options considered

| Option | Benefit | Cost / risk | Decision |
|---|---|---|---|
| 1. Inspector column (sender + chat) | Matches “sidebar while browsing”; progressive disclosure | Layout + new chat surface | **Selected** |
| 2. Detached assistant window | Faster; less layout risk | Leaves reading flow | Rejected |
| 3. Unified AI rail (compose + read + mailbox) | One mental model | Blurs consent/scopes; large redesign | Rejected |

## Product principles

- **Mail first.** Reading remains the primary surface; the column is opt-in.
- **Local facts are free; AI is gated.** Opening the column / sender panel
  does not contact an AI provider or any new network endpoint.
- **AI is invoked, never automatic** (ADR-0028 invariant 6).
- **AI may interpret and answer; only the deterministic planner + user
  confirmation may mutate** (ADR-0026).
- **Capability-driven UI**; views never type-check backends.
- **Theme tokens only**; no literal colors in views.

## Layout and shell (macOS)

```text
┌──────────┬─────────────┬──────────────────┬─────────────────────┐
│ Sidebar  │ Message     │ Reader           │ Mail Context        │
│ folders  │ list        │ selected mail    │ (toggleable)        │
│          │             │                  │ ┌─────────────────┐ │
│          │             │                  │ │ Sender panel    │ │
│          │             │                  │ ├─────────────────┤ │
│          │             │                  │ │ Mailbox chat    │ │
│          │             │                  │ └─────────────────┘ │
└──────────┴─────────────┴──────────────────┴─────────────────────┘
```

| Rule | Detail |
|---|---|
| Open | Toolbar button + keyboard shortcut (exact chord chosen at implement time; document in CHANGELOG) |
| Default | Closed |
| Selection | When open, message selection refreshes the sender panel; chat transcript is not wiped on selection change |
| Width | Resizable with min / ideal / max (same pattern as `MailPaneColumnWidthPolicy`) |
| Collapse | Closing preserves session transcript; reopening restores it |
| Empty selection | Sender panel: “Select a message”; chat remains usable with last sender scope or a prompt to select |
| Density / theme | Uses existing density metrics and `brevTheme` tokens |
| Vertical split | Sender panel above chat; user-resizable split preferred if cheap, otherwise a fixed sensible ratio |

## Sender panel (local-only)

| Block | Content |
|---|---|
| Identity | Avatar, display name, email; contact match when `ContactLookupProviding` is available |
| Relationship | First/last seen and message count for this sender in the current account when the local index can answer cheaply |
| Recent mail | Last **8** headers from this sender: subject, date, folder; tap navigates to that message |
| Quick actions | Reply / Reply All / Forward for the **selected** message; “Show all from sender” via local search |
| States | Skeleton while loading; “No local history yet” when empty; cancel in-flight work on selection change |

| Rule | Detail |
|---|---|
| Correspondent | Primary From of the selected message (same reply-relevant policy as compose reply addressing where applicable) |
| Privacy | Headers + contact metadata only — do not fetch bodies for the panel |
| Network | Zero network on panel open; local index / cache / contacts only |
| Account scope | Selected message’s `MailSourceID` / account |

## Mailbox chat

### Consent and transparency

| Rule | Detail |
|---|---|
| Enablement | Reuse AI Writer enable + consent for v1 (avoid a second dual prompt). Settings copy should mention mailbox chat if needed. |
| Transparency | Every assistant turn shows the destination label (`Sent to: …`) |
| Off state | Input disabled with “Enable AI…” → consent / Settings |
| Invocation | Only when the user sends a chat message |

### Scope

| Rule | Detail |
|---|---|
| Default | **Current sender** — visible chip above the input |
| Widen | Folder / Account shipped in #309 follow-up; Sender remains the default chip |
| Q&A context | Local search within scope → bounded headers/snippets (message and byte caps; align with #305 AI safety policy) |
| Citations | Answers cite subject/date and openable message references |

### Response modes

| Mode | Trigger | Behavior |
|---|---|---|
| Answer | Informational question | Generated answer + citations; no mutations |
| Action proposal | Delete / move / archive-style intent | Optional AI intent interpretation → `MailboxActionAgentPlanner` → inline review card with sender, folder, count → user types confirmation phrase (`DELETE N` / `MOVE N`) → then `MailBackend` mutation |

Ambiguous or unsupported intents return clarification (ADR-0026). The AI
runtime has no mutation tools and must not call `MailBackend`.

### Chat UI behavior

- Session-local transcript (user / assistant); streaming when the backend supports it
- Send + cancel in-flight
- Action proposals render as inline cards (never auto-applied)
- Transcript is not uploaded to a Brev service and is not durable mailbox metadata in v1

## Architecture

```text
Message selection
       │
       ▼
MailContextColumn (BrevMail, macOS)
  ├─ SenderContextPanel ──► SenderContextLoader (local index + ContactLookup)
  └─ MailboxChatPanel
        ├─ scope chip (Sender)
        ├─ session transcript store
        └─ MailboxChatController
              ├─ Q&A: local search → bounded context → AIBackend
              └─ Action: AI intent (optional) → MailboxActionAgentPlanner
                         → confirm UI → MailBackend
```

| Unit | Responsibility |
|---|---|
| `MailContextColumn` | Column chrome, open state, vertical split |
| `SenderContextModel` | Pure snapshot for identity, counts, recent headers |
| `MailboxChatController` | Answer vs action routing, streaming, handoff to planner |
| `MailboxActionAgentPlanner` | Existing mutation authority (reuse; do not fork) |

### Boundaries

- Views never import Realm or provider-specific types.
- Capability-driven AI availability (`.aiWriter` / related flags as appropriate).
- Opening the column or loading the sender panel must remain zero-network.
- Before shipping AI chat turns: update ADR-0006 network table, `PRIVACY.md`,
  and either extend ADR-0026/0042 or add a small ADR for mailbox chat Q&A
  context leaving the device.

### Wiring gap to close

Root `.mailboxAssistant` currently presents `EmptyView()`. v1 must host
supervised confirmation inside the chat action card (preferred) and/or restore
a working presentation path so mutations are not dead UI.

## Error handling

| Case | Behavior |
|---|---|
| No AI backend / unsupported account | Chat disabled with clear reason |
| Consent missing | Enable flow; no silent send |
| Local search empty | Honest empty answer; no hallucinated citations |
| AI failure / cancel | Inline error; transcript remains |
| Action plan clarification | Show clarification; no confirm phrase yet |
| Mutation failure after confirm | Surface error; do not pretend success |
| Selection change mid-sender-load | Cancel prior load; show new sender |

## Testing and verification

| Layer | Coverage |
|---|---|
| Unit | Sender snapshot construction; default scope; answer vs action routing; confirm-before-mutate; context byte/message caps |
| UI / snapshot | Column closed/open; empty selection; AI off; action review card |
| Privacy | `scripts/privacy-audit.sh` when AI network path is added; no network on panel open |
| Manual macOS | Toggle shortcut; select messages; Q&A with citations; delete/move confirm phrase |

## Relationship to existing AI surfaces

| Surface | Role after this ships |
|---|---|
| Compose AI Writer | Unchanged — draft rewrite / prompt / subject in compose |
| Thread Summarize | Unchanged — manual summary in reader controls |
| Mail Context chat | New — ask / act on mailbox while browsing |
| Mailbox Assistant sheet | Logic reused; presentation migrates into chat action cards |

## Implementation sequencing (hint for plan)

1. Column shell + toggle + empty/selection states (no AI).
2. Sender panel local loader + recent headers + quick actions.
3. Chat UI shell + consent gate + Sender scope chip (no network answers yet optional stub).
4. Q&A path with local search + bounded AI context + citations + privacy/ADR updates.
5. Action path wired through existing planner + typed confirm.
6. Tests, snapshots, CHANGELOG, worklog.

## Success criteria

- User can open/close a right Mail Context column on macOS without disrupting the three-pane scan/read loop.
- Sender panel shows useful local identity and recent mail with no AI and no new network calls.
- Chat can answer sender-scoped questions with citations when AI is enabled and consented.
- Chat can propose sender-scoped mailbox actions that only run after review + typed confirmation.
- Privacy posture remains explicit and documented.

## Open implementation details (non-blocking)

- Exact keyboard shortcut chord
- Whether vertical split is user-resizable in v1
- Whether Folder/Account scope chips ship disabled or are deferred entirely after Sender — **resolved:** selectable in #309 when context is available
- Shared vs separate Settings copy for “mailbox chat” under AI Writer
