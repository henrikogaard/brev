# iOS and iPadOS Surface QA Matrix

Use this checklist before iOS beta builds and after substantial iOS/iPadOS UI
changes. Record the exact simulator/device, OS version, appearance, content
size, and any skipped rows in a dated result file under `docs/qa/results/`.

## Required Environments

| Environment | Required coverage |
| --- | --- |
| iPhone | Current primary iPhone simulator or physical device |
| iPad | Current primary iPad simulator or physical device |
| Appearance | Light and dark, or record which appearance was skipped |
| Dynamic Type | Default plus one accessibility size, or record why skipped |
| Orientation | Portrait on iPhone; portrait or landscape/split layout on iPad |
| Data mode | Demo/mock mailbox; live mailbox only when credentials are available |

## Checklist

| Surface | iPhone result | iPad result | Evidence to record |
| --- | --- | --- | --- |
| Login/demo entry | Pass/Fail/Skipped | Pass/Fail/Skipped | Login/demo controls visible and usable |
| Mailbox/folder navigation | Pass/Fail/Skipped | Pass/Fail/Skipped | Profile/source rows, folders, counts, and selection state |
| Message list | Pass/Fail/Skipped | Pass/Fail/Skipped | Rows, grouped headers, toolbar, quick filters, footer counts |
| Message reader | Pass/Fail/Skipped | Pass/Fail/Skipped | Selected message/thread opens with command toolbar |
| Compose | Pass/Fail/Skipped | Pass/Fail/Skipped | New/reply compose, recipients, subject/body, attachments, send controls |
| Settings | Pass/Fail/Skipped | Pass/Fail/Skipped | Settings entry, sidebar/stack navigation, close affordance |
| Profiles/accounts | Pass/Fail/Skipped | Pass/Fail/Skipped | Account/profile rows, mailbox switches, default/add controls |
| Search and filters | Pass/Fail/Skipped | Pass/Fail/Skipped | Search field, sort/filter chips, result count behavior |
| Dark mode | Pass/Fail/Skipped | Pass/Fail/Skipped | No unreadable chrome, clipped text, or black system bands |
| Dynamic Type | Pass/Fail/Skipped | Pass/Fail/Skipped | Largest tested size keeps primary controls reachable |
| iPad split view/sidebar | Not applicable | Pass/Fail/Skipped | Sidebar toggle, list/detail columns, selected-message detail |
| External keyboard basics | Pass/Fail/Skipped | Pass/Fail/Skipped | Tabbable/focusable primary controls or documented manual pass |
| Offline/empty/error states | Pass/Fail/Skipped | Pass/Fail/Skipped | Offline banner, empty list/detail, login/setup error copy |

## Follow-up Rules

- Convert every failed row into a focused GitHub issue before marking the QA
  pass complete.
- Link the result file from the GitHub issue or release handoff.
- Do not store screenshots containing private mail. Demo/mock screenshots are
  acceptable when they add useful visual evidence.
