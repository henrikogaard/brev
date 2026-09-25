# Stub DAV seed

Canonical fixture set for `scripts/stub-dav-server.py` — identical data on
every run and every platform so PIM surfaces (Calendar, Contacts, Tasks)
always show the same content in mock-mode testing.

```sh
python3 scripts/stub-dav-server.py --port 8643 --auth stub:stubpass \
    --seed scripts/stub-dav-seed --log /tmp/davstub-requests.log
```

Then add a CalDAV/CardDAV source in Settings → Calendar & Contacts pointing
at `http://127.0.0.1:8643` with `stub` / `stubpass`.

Contents: two events, one task (`harbour-data` — NEEDS-ACTION), two contacts
(Harbour Logistics crew).
