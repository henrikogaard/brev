# Brev design direction

This file records durable visual intent. Runtime values remain owned by
`BrevTheme`, `BrevFont`, `BrevSpacing`, and `BrevRadius`; ADR-0002 remains the
architectural source of truth for theme tokens.

## Product character

Brev is a calm, direct mail client for people who want Gmail, Google Workspace,
and standards-based mail in one native Apple app. The interface should feel
quietly capable rather than decorative: clear hierarchy, restrained controls,
and visible proof that account access stays between the provider and the user's
device.

## Visual system

The default Brev Mono Light and Brev Mono Dark themes define the reference
palette. All views consume the semantic roles below; they never copy these
values locally.

| Role | Mono Light | Mono Dark | Runtime owner |
| --- | --- | --- | --- |
| Canvas | `#FFFFFF` | `#101010` | `theme.bgPrimary` |
| Quiet surface | `#F5F5F5` | `#1A1A1A` | `theme.bgSecondary` |
| Primary ink | `#151515` | `#F2F2F2` | `theme.textPrimary` |
| Secondary ink | `#505050` | `#B8B8B8` | `theme.textSecondary` |
| Primary action | `#1F1F1F` | `#E6E6E6` | `theme.accent` |
| Hairline | `#D8D8D8` | `#333333` | `theme.border` |

Typography stays native and Dynamic Type aware:

- Display: SF Pro Display through `BrevFont.largeTitle` and `BrevFont.title`.
- Body: SF Pro Text through `BrevFont.body` and `BrevFont.callout`.
- Utility: SF Pro Text through `BrevFont.footnote` and `BrevFont.caption`.

Use the existing 4-point spacing scale. Prefer asymmetric compositions with a
clear reading order over centered cards. Use proximity and whitespace before
adding borders or surfaces. Reserve the accent for the primary action and
meaningful state; preserve semantic status colors and the Brev app icon.

Native product surfaces use a restrained Scandinavian hierarchy:

- left-aligned system typography with no decorative font treatment;
- no shadow or glow unless it communicates real elevation;
- no card when spacing can express the same grouping;
- no decorative line, icon, or label that repeats nearby copy;
- one filled primary action per task surface.

The first-run wordmark uses the shipped Brev app-icon artwork from the shared
`BrevMail` resource bundle, rendered at 48 points on compact layouts and 52
points on wide layouts. Do not replace it with a generic envelope symbol or add
a decorative shadow around it.

The built-in themes remain product-wide user choices. A screen may not create a
second local palette or override them with literal neutral colors; it should
instead avoid introducing additional tinted surfaces and decorative accents.
First launch follows the operating system appearance without pinning light or
dark. Brev Mono Light and Brev Mono Dark are the defaults; explicit Always
Light, Always Dark, saved theme pairs, and legacy themes still preserve their
selected appearance. Semantic state colors and identity content may remain
colored because monochrome must not erase meaning.

## First-run account connection

The screen has one job: help a new user connect a first mailbox with confidence.
Gmail and Google Workspace are the primary path; generic IMAP/SMTP is the clear
secondary path; the demo mailbox is a tertiary preview.

Wide composition:

```text
+------------------------------------------------------------------+
| [icon] Brev                                                      |
|                                                                  |
| Connect your mailbox.      Choose how to connect                 |
| Gmail, Workspace, and      [ Continue with Google             ]  |
| IMAP in one place.         [ Use another mail account         ]  |
|                            Preview sample mail                   |
|                            Credentials stay in the Keychain      |
+------------------------------------------------------------------+
```

Compact composition:

```text
+--------------------------------+
| [icon] Brev                    |
| Connect your mailbox.          |
| Gmail, Workspace, and IMAP.    |
|                                |
| Choose how to connect          |
| [ Continue with Google      ]  |
| [ Use another mail account  ]  |
| Preview sample mail            |
| Credentials stay in Keychain   |
+--------------------------------+
```

The account choices form one unboxed task column. Supporting copy stays next to
the action it explains, and the Keychain note closes the sequence without a
decorative route or extra boundary.

## Interaction and accessibility

- Keep one filled primary action; secondary and preview actions use established
  `BrevButton` styles.
- Preserve visible recovery, pending, cancel, and unavailable states without
  moving the primary controls unexpectedly.
- Keep controls keyboard reachable, preserve the default-action shortcut, and
  provide useful accessibility labels and hints.
- Let content scroll at compact heights and under large Dynamic Type sizes.
- Respect the active Brev theme and Reduced Motion; onboarding does not require
  ambient animation.


## Mailbox navigation

Profiles are saved sets of mailboxes, such as Work or Private. Use one compact,
stable profile menu at the top of the sidebar, with profile choices and Manage
Profiles directly inside it. A mailbox click or opened message must not rename
that profile control or change the active profile.

Stack the profile's mailboxes as independently collapsible groups. Each has a
compact one-line header and its own folder tree, so users can keep several
inboxes and folder sets visible together. Preserve expansion choices locally
across profile changes and relaunches. Selecting a folder does not collapse
other mailboxes; reading a message from a global view does not expand a group.

Addresses belong in tooltips and accessibility labels. Omit the extra Mailboxes
heading, permanent email-address lines, and a separate folder-owner caption:
the mailbox group owns its tree. Show unread counts beside folders and on
collapsed mailbox headers. All Inboxes appears for multiple visible mailboxes
and aggregates only the active profile. Smart Views remain collapsible.

Use a native borderless menu with a visible disclosure indicator on macOS.
Touch platforms retain at least a 44-point target. Reuse the existing navigation
and profile callbacks; profile changes never disconnect accounts.
