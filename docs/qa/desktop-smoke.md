# Desktop Smoke Checklist

Use this checklist when deciding whether the macOS app is working well
enough to daily-drive or package for beta. Run mock mode first, then
repeat the live sections with a Gmail account and a generic IMAP/SMTP
test account once local OAuth and mailbox setup are ready.

## Prerequisites

- [ ] `scripts/desktop-smoke-mock.sh` exits `0` for the automated
      no-OAuth smoke gate.
- [ ] `scripts/desktop-compact-layout-check.sh` exits `0` for the
      deterministic compact-window source contract.
- [ ] `scripts/privacy-audit.sh` exits `0`.
- [ ] `scripts/release-preflight.sh` reports no hard errors on the
      machine that will create the beta build.
- [ ] `scripts/test.sh` exits `0`.
- [ ] `scripts/format.sh` exits `0` and reports no formatted files.
- [ ] `scripts/lint.sh` exits `0`.
- [ ] `git diff --check` exits `0`.
- [ ] The literal-color scan exits `1` with no matches:
  ```bash
  rg -n "Color\.(black|blue|brown|cyan|gray|green|indigo|mint|orange|pink|purple|red|teal|white|yellow)|Color\(hex:|#[0-9A-Fa-f]{3,8}" apps packages/BrevDesign/Sources packages/BrevMail/Sources packages/BrevSettings/Sources
  ```
- [ ] For live mode, `./script/build_and_run.sh --preflight --live`
      reports `preflight: live OAuth configuration ready`.

## Mock Mode

- [ ] `./script/build_and_run.sh --mock --verify` builds and launches
      Brev.
- [ ] The app opens directly to the mock mailbox.
- [ ] Sidebar folders are visible and selectable.
- [ ] Message list rows show sender, subject, preview, date, unread
      state, and flag state.
- [ ] Selecting a message opens the reading pane without replacing
      the sidebar or list.
- [ ] Quitting and relaunching in mock mode opens without stale sheet
      or selection errors.

## Live OAuth

- [ ] `./script/build_and_run.sh --live --logs` launches the login
      screen.
- [ ] Pressing Sign in opens the system browser authentication sheet.
- [ ] Successful login returns through the callback configured for the tested
      provider and platform: macOS Google uses
      `http://127.0.0.1:<ephemeral-port>/oauth2redirect`, iOS Google uses the
      reversed-client-ID scheme ending in `:/oauth2redirect`, and Microsoft
      uses `brev://oauth`.
- [ ] The login screen transitions to the mail UI.
- [ ] OAuth tokens are stored in Keychain and are not printed in logs.
- [ ] Relaunch restores the signed-in account without another browser
      prompt.
- [ ] Sign out removes the active account session and returns to the
      login screen.
- [ ] Signing in again after sign-out works without restarting the app.

## Mailbox And Folder Sync

- [ ] Inbox, Sent, Drafts, Archive, Trash, and custom folders appear
      when the account has them.
- [ ] Folder unread and total counts update after refresh.
- [ ] Switching folders clears stale message-body state.
- [ ] Switching mailboxes preserves account identity and shows the
      correct sender address for outgoing mail.
- [ ] A failed folder or mailbox load shows a readable retry state.
- [ ] Retrying a failed load does not duplicate folders or messages.

## Message List

- [ ] First page loads newest-first.
- [ ] Load more appends the next page without losing selection.
- [ ] Search for a term returns matching messages.
- [ ] Clearing search restores the current folder list.
- [ ] Opening a search result outside Inbox loads the correct body.
- [ ] Quick-filter chips (Unread, Flagged, Attachments, Today, Last week)
      filter the loaded message list without a backend round-trip.
- [ ] Multiple quick-filters can be active simultaneously; messages must
      match all active filters.
- [ ] Empty folders show an empty state, not a spinner.
- [ ] Transport or API errors show a retryable status.

## Reading Pane

- [ ] Plain text messages render readable body content.
- [ ] HTML messages render inside the body pane.
- [ ] Remote HTML assets are blocked by default.
- [ ] Enabling remote content for one message does not globally enable
      it for other messages.
- [ ] Links open externally instead of navigating inside the message
      web view.
- [ ] Attachment rows show filename, type, and size when available.
- [ ] Downloading an attachment writes a file and exposes Quick Look
      on macOS.
- [ ] Opening an unread message marks it read once.
- [ ] Mark-read rollback restores unread state if the backend mutation
      fails.

## Calendar Invites

- [ ] A message with a supported `.ics` attachment shows the calendar
      invite card.
- [ ] Event title, time, location, organizer, and attendee status are
      visible when the backend provides them.
- [ ] Accept, Maybe, and Decline are visible only when
      `.serverSideCalendarReply` is available.
- [ ] Accept updates the local card state and does not leave a stuck
      spinner.
- [ ] Maybe updates the local card state and does not leave a stuck
      spinner.
- [ ] Decline updates the local card state and does not leave a stuck
      spinner.
- [ ] A malformed invite shows a readable error state.

## Compose

- [ ] Compose opens from the toolbar, menu, and keyboard shortcut.
- [ ] Recipient chips commit on Return, Tab, comma, and focus loss.
- [ ] Invalid recipient text remains editable and does not crash send.
- [ ] Save draft creates a draft in Drafts.
- [ ] Editing a saved draft updates the same draft instead of creating
      a duplicate.
- [ ] Send moves the message to Sent.
- [ ] Reply prefixes the subject once and quotes useful original
      context.
- [ ] Reply All includes the expected original recipients without
      duplicating the active identity.
- [ ] Forward prefixes the subject once and includes original message
      context.
- [ ] Attaching files sanitizes local filenames before display and
      upload.
- [ ] Removing a pending attachment before send excludes it.
- [ ] Upload or send failure leaves the compose sheet open with a
      readable error.
- [ ] With AI Writer enabled, selecting body text and right-clicking
      the compose editor shows selected-text rewrite actions; choosing
      one sends only the highlighted text.
- [ ] A selected-text AI rewrite replaces only the highlighted range
      and does not overwrite the rest of the draft if the body or
      selection changed while the request was in flight.
- [ ] AI Writer output appears in the composer preview panel before it
      changes the draft; Replace, Insert at Cursor, Copy, Try Again,
      and Cancel behave according to the current target and cursor.
- [ ] The AI preview and compose menu show the provider transparency
      label before generated text can be applied.
- [ ] Draft from Prompt asks for an explicit prompt and previews the AI
      draft before inserting or replacing body text.
- [ ] Draft Reply is available only from reply compose context and
      previews the generated reply before changing the draft.
- [ ] Suggest Subject previews a generated subject line and applies it
      only through Replace Subject.
- [ ] On an account/backend without `.aiWriter` capability, the compose
      AI menu and settings AI row show a disabled unsupported-account
      explanation instead of silently hiding AI Writer.
- [ ] On iOS, selected body text can use the same rewrite actions from
      the compose AI menu's selection path when the native edit menu
      does not expose custom actions.

## Thread / Conversation View

- [ ] A multi-message thread row in the list shows a count badge (e.g.
      "3").
- [ ] Tapping/clicking the disclosure chevron expands the thread inline,
      showing indented child rows sorted oldest→newest.
- [ ] Tapping a child row selects that individual message and opens it in
      the reading pane.
- [ ] Collapsing the thread hides the child rows and returns to the
      parent row display.
- [ ] Opening a multi-message thread opens the conversation reading pane
      (ThreadConversationView) showing all messages as stacked cards.
- [ ] The newest card is expanded by default; older cards are collapsed.
- [ ] Tapping a collapsed card expands it and lazily loads its body.
- [ ] Scrolling within the conversation pane works smoothly.
- [ ] Opening a single-message thread opens the standard reading pane
      (not a thread conversation view).

## Fetch Schedule

- [ ] Settings → Accounts shows a "Fetch schedule" group with an
      interval picker (Manually / Every 5 min / Every 15 min / Every 30
      min / Every hour) and a background fetch toggle.
- [ ] Selecting "Manually" stops any automatic polling; Get Mail still
      works from the toolbar.
- [ ] Selecting a polling interval fires a background refresh at
      approximately that interval while the app is in the foreground.
- [ ] Changing the interval restarts the scheduler with the new interval
      without requiring an app relaunch.
- [ ] Background fetch disabled disables the toggle text as expected.

## Junk and Block Sender

- [ ] Right-clicking a message in the list shows "Mark as Junk" when the
      backend advertises the `.junkAPI` capability.
- [ ] "Mark as Junk" removes the message from the current folder
      (optimistically) and moves it to the spam/junk folder.
- [ ] Right-clicking a message in the spam folder shows "Mark as Not
      Junk" instead of "Mark as Junk".
- [ ] "Mark as Not Junk" moves the message back to the inbox.
- [ ] Right-clicking a message shows "Block Sender…" when the backend
      advertises `.blockSender`.
- [ ] "Block Sender…" shows a confirmation alert with the sender email
      before executing.
- [ ] Cancelling the block-sender alert does not move the message.
- [ ] Both actions are hidden or disabled when the backend does not
      advertise the corresponding capability.

## Message Commands

- [ ] Refresh is disabled or ignored while another refresh is active.
- [ ] Toolbar, menu, and context-menu commands agree on enabled state.
- [ ] Mark Read and Mark Unread mutate the selected message and update
      counts.
- [ ] Flag and Unflag mutate the selected message and update indicators.
- [ ] Archive moves the selected message out of Inbox.
- [ ] Move to Folder shows available destination folders in the context
      menu and moves the selected message on selection.
- [ ] Delete moves a non-Trash message to Trash.
- [ ] Delete permanently removes a Trash message only when the backend
      says that is the current folder semantics.
- [ ] Dragging a message to another folder moves it and refreshes the
      visible list.
- [ ] Command failures roll back optimistic UI state.
- [ ] Background refresh, folder reload, and message mutations do not
      overlap in a way that leaves stale selection.

## Settings And Privacy

- [ ] Accounts section shows stored accounts and backend badges.
- [ ] Add account is disabled while sign-in or sign-out work is active.
- [ ] Privacy section defaults to local Contacts on and external avatar
      sources off.
- [ ] Turning Gravatar on updates visible avatars after cache refresh.
- [ ] Turning BIMI on updates visible avatars after cache refresh.
- [ ] Turning favicons on updates visible avatars after cache refresh.
- [ ] Turning all external avatar sources off returns to Contacts or
      initials only.
- [ ] Clear cached avatars discards previously resolved external
      images.
- [ ] AI Writer is off by default.
- [ ] Enabling AI Writer requires explicit consent.
- [ ] Disabling AI Writer prevents compose AI actions from sending
      content.
- [ ] BYOK/local provider panel is hidden until its v2 flag is enabled.
- [ ] When a BYOK/local provider is configured, each AI invocation
      shows a clear "Sent to: <provider/host>" label before generated
      text is applied.
- [ ] BYOK/local provider configuration rejects invalid endpoint URLs and
      model IDs during save.
- [ ] Local/Ollama setup does not probe localhost or make public-internet
      calls during configuration; calls occur only after the user
      explicitly invokes an AI action.
- [ ] API keys are never shown in plaintext after save; saved key previews
      and status text are redacted.
- [ ] Removing a BYOK/local provider deletes its stored API key from the
      device Keychain.

## Window, Toolbar, And Keyboard

- [ ] The native macOS toolbar appears in the main window.
- [ ] The main toolbar does not draw a static “Brev” title; native traffic-light
      controls and toolbar actions remain visible and usable.
- [ ] `scripts/desktop-compact-layout-check.sh --runtime --screenshot /tmp/brev-compact-960x600.png`
      launches mock mode, validates the 960x600 SwiftUI content
      contract, and exits `0`. System Events reports the outer AppKit
      window frame, so the runtime size may include native
      titlebar/toolbar chrome, for example 960x652. If macOS blocks
      System Events, the script falls back to WindowServer visibility
      evidence and prints `runtime partial OK`; grant Accessibility
      permission to Terminal/Codex or resize the mock-mode content area
      manually to 960x600 for full visual verification.
- [ ] At 960x600, the sidebar, message list, and reading pane remain
      simultaneously visible.
- [ ] Toolbar icons fit at 960x600 without clipped labels, overlapping
      controls, or hidden command items that are expected in the
      default toolbar.
- [ ] Compact inline status surfaces, mailbox controls, and selection
      highlights do not overlap the message list or reading pane.
- [ ] Message menu shortcuts work for compose, reply, reply-all,
      forward, archive, delete, toggle read, toggle flag, refresh,
      next message, and previous message.
- [ ] Sheet presentation does not replace an already-open sheet.
- [ ] Window relaunch does not leave disabled toolbar items stuck.

## Logging And Local Data

- [ ] Logs contain useful request phase errors without access tokens,
      refresh tokens, authorization codes, message body content, or
      attachment bytes.
- [ ] Account metadata is stored outside Keychain only when it is not a
      credential.
- [ ] Signing out clears the token for that account.
- [ ] A transient backend failure preserves the stored account for a
      later retry.
- [ ] An authentication-required backend failure clears the stale token
      and account.

## Release Readiness

- [ ] The app passes the mock checklist from a clean build directory.
- [ ] The app passes the live checklist with a real mailbox.
- [ ] `PRIVACY.md` matches every implemented external network call.
- [ ] `ADRs/0006-telemetry-and-privacy.md` matches `PRIVACY.md`.
- [ ] `CHANGELOG.md` has an Unreleased entry for the tested change
      set.
- [ ] No banned telemetry imports are present.
- [ ] No `RealmSwift` imports are present outside allowed backend boundaries.
