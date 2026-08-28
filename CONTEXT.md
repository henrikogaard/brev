# Brev domain language

## Mail notification delivery

- **Local notification**: an alert Brev creates on the device after a local
  mailbox refresh observes new mail.
- **Live sync**: IMAP IDLE or provider history polling while Brev is running.
- **Background refresh**: a best-effort mailbox refresh during an operating
  system-granted background execution window.
- **Remote push**: an APNS alert initiated by a mail provider or Brev-operated
  server while Brev is not running. Brev `0.1.0` does not provide remote push.
