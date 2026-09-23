#!/usr/bin/env python3
# MIT License — Copyright (c) 2026 Brev Contributors
#
# Minimal CalDAV/CardDAV stub for local verification of Brev's DAV paths
# (see docs/qa/pim-parity-matrix.md). Not a real DAV server — just enough
# RFC 4791/6352/6578 surface for the client to exercise connect, sync,
# and conditional write flows against a live socket.
#
# Usage:
#   scripts/stub-dav-server.py --port 8643 [--auth user:pass]
#       [--seed dir-with-.ics/.vcf] [--log requests.log]
#
# Control endpoints (never authed):
#   GET  /__control/log            — request log so far
#   POST /__control/add            — inject a remote item:
#                                    {"href": "/cal/u/main/x.ics", "body": "..."}
#   POST /__control/expire-sync    — mark all issued sync-tokens expired;
#                                    next sync-collection REPORT answers
#                                    DAV:valid-sync-token so the client resyncs
#
# Layout served:
#   /                    — endpoint; PROPFIND exposes principal + home sets
#   /principals/u/       — current-user-principal target
#   /cal/u/              — calendar home set; /cal/u/main/ VEVENT+VTODO
#   /card/u/             — addressbook home set; /card/u/main/ addressbook

import argparse
import base64
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from xml.sax.saxutils import escape

STATE = {
    "items": {},          # href -> {"body": str, "etag": str}
    "sync_epoch": 1,      # bumped on every mutation
    "expired_epochs": set(),
    "auth": None,         # (user, pass) or None
    "log": [],            # request log lines
}

NS = (
    'xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" '
    'xmlns:card="urn:ietf:params:xml:ns:carddav" '
    'xmlns:cs="http://calendarserver.org/ns/" '
    'xmlns:ical="http://apple.com/ns/ical/"'
)


def log_line(line):
    STATE["log"].append(line)
    print(line, flush=True)


def multistatus(*responses):
    return (
        f'<?xml version="1.0" encoding="utf-8"?>\n'
        f'<d:multistatus {NS}>' + "".join(responses) + "</d:multistatus>"
    )


def propstat(href, props, status="HTTP/1.1 200 OK"):
    return (
        f"<d:response><d:href>{escape(href)}</d:href>"
        f"<d:propstat><d:prop>{props}</d:prop>"
        f"<d:status>{status}</d:status></d:propstat></d:response>"
    )


def principal_props():
    return (
        "<d:current-user-principal><d:href>/principals/u/</d:href>"
        "</d:current-user-principal>"
        "<cal:calendar-home-set><d:href>/cal/u/</d:href></cal:calendar-home-set>"
        "<card:addressbook-home-set><d:href>/card/u/</d:href>"
        "</card:addressbook-home-set>"
    )


def collection_props(kind):
    if kind == "calendar":
        return (
            "<d:resourcetype><d:collection/><cal:calendar/></d:resourcetype>"
            "<d:displayname>Stub Calendar</d:displayname>"
            "<cal:supported-calendar-component-set>"
            '<cal:comp name="VEVENT"/><cal:comp name="VTODO"/>'
            "</cal:supported-calendar-component-set>"
            "<cs:getctag>ctag-cal-%d</cs:getctag>"
            "<d:sync-token>http://stub/sync/%d</d:sync-token>"
            "<ical:calendar-color>#3A7BD5</ical:calendar-color>"
        ) % (STATE["sync_epoch"], STATE["sync_epoch"])
    return (
        "<d:resourcetype><d:collection/><card:addressbook/></d:resourcetype>"
        "<d:displayname>Stub Contacts</d:displayname>"
        "<cs:getctag>ctag-card-%d</cs:getctag>"
        "<d:sync-token>http://stub/sync/%d</d:sync-token>"
        '<card:addressbook-color>#7B51C6</card:addressbook-color>'
    ) % (STATE["sync_epoch"], STATE["sync_epoch"])


def is_collection_path(path, kind):
    return path.rstrip("/") == f"/{kind}/u/main"


def home_set(path):
    if path.rstrip("/") in ("/cal/u",):
        return "cal"
    if path.rstrip("/") in ("/card/u",):
        return "card"
    return None


def item_props(href, include_data=False):
    item = STATE["items"].get(href)
    if item is None:
        return propstat(href, "<d:getetag/>", "HTTP/1.1 404 Not Found")
    props = f"<d:getetag>{escape(item['etag'])}</d:getetag>"
    if include_data:
        if href.endswith(".ics"):
            props += f"<cal:calendar-data>{escape(item['body'])}</cal:calendar-data>"
        else:
            props += f"<card:address-data>{escape(item['body'])}</card:address-data>"
    return propstat(href, props)


def collection_of(href):
    parts = href.split("/")
    return "/".join(parts[:-1]) + "/" if len(parts) > 1 else "/"


class StubDAV(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        pass

    # -- plumbing ---------------------------------------------------------

    def _read_body(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        return self.rfile.read(length) if length else b""

    def _authorized(self):
        if self.path.startswith("/__control/") or STATE["auth"] is None:
            return True
        header = self.headers.get("Authorization", "")
        user, pw = STATE["auth"]
        expected = "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode()
        return header == expected

    def _record(self, status):
        auth = "Basic ***" if "Authorization" in self.headers else "-"
        depth = self.headers.get("Depth", "-")
        match = self.headers.get("If-Match", self.headers.get("If-None-Match", "-"))
        log_line(f"{self.command} {self.path} depth={depth} auth={auth} cond={match} -> {status}")

    def _send(self, status, body=b"", content_type="application/xml; charset=utf-8", etag=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if etag:
            self.send_header("ETag", etag)
        self.end_headers()
        if body:
            self.wfile.write(body)
        self._record(status)

    def _reject_auth(self):
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="stubdav"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(401)

    def _gate(self):
        if not self._authorized():
            self._reject_auth()
            return False
        return True

    # -- control ----------------------------------------------------------

    def _control(self):
        if self.path == "/__control/log":
            self._send(200, "\n".join(STATE["log"]) + "\n", "text/plain")
        elif self.path == "/__control/expire-sync":
            STATE["expired_epochs"].add(STATE["sync_epoch"])
            self._send(200, "ok\n", "text/plain")
        elif self.path == "/__control/add" and self.command == "POST":
            payload = json.loads(self._read_body() or b"{}")
            self._store(payload["href"], payload["body"])
            self._send(200, "ok\n", "text/plain")
        else:
            self._send(404, "nope\n", "text/plain")

    # -- DAV verbs --------------------------------------------------------

    def do_OPTIONS(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        self.send_response(200)
        self.send_header("DAV", "1, 2, 3, calendar-access, addressbook, sync-collection")
        self.send_header("Allow", "OPTIONS, PROPFIND, REPORT, GET, PUT, DELETE")
        self.send_header("Content-Length", "0")
        self.end_headers()
        self._record(200)

    def do_PROPFIND(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        self._read_body()
        path = self.path.rstrip("/") or "/"
        depth = self.headers.get("Depth", "0")

        if path in ("", "/", "/principals/u"):
            # Endpoint + principal: expose principal and both home sets.
            self._send(207, multistatus(propstat(path + "/", principal_props())))
            return
        if home_set(path) and depth == "1":
            kind = home_set(path)
            coll = f"/{kind}/u/main/"
            body = multistatus(
                propstat(path + "/", "<d:resourcetype><d:collection/></d:resourcetype>"),
                propstat(coll, collection_props("calendar" if kind == "cal" else "addressbook")),
            )
            self._send(207, body)
            return
        if is_collection_path(path, "cal") or is_collection_path(path, "card"):
            # Depth:1 collection listing: href + etag per member.
            prefix = path.rstrip("/") + "/"
            members = [
                item_props(href)
                for href in sorted(STATE["items"])
                if collection_of(href) == prefix
            ]
            members.insert(0, propstat(prefix, collection_props(
                "calendar" if "/cal/" in prefix else "addressbook")))
            self._send(207, multistatus(*members))
            return
        self._send(404, "<html>not found</html>", "text/html")

    def do_REPORT(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        body = self._read_body().decode(errors="replace")
        path = self.path.rstrip("/") + "/"

        if "<d:sync-collection" in body or "<sync-collection" in body:
            token = ""
            if "<d:sync-token>" in body:
                token = body.split("<d:sync-token>")[1].split("</d:sync-token>")[0].strip()
            epoch = _epoch_of(token)
            if token and epoch in STATE["expired_epochs"]:
                self._send(403, multistatus(
                    "<d:error><d:valid-sync-token/></d:error>"), )
                return
            inline = "<cal:calendar-data" in body or "<c:calendar-data" in body \
                or "<card:address-data" in body or "<c:address-data" in body
            members = [
                item_props(h, include_data=inline)
                for h in sorted(STATE["items"]) if collection_of(h) == path
            ]
            self._send(207, multistatus(
                *members,
                f"<d:sync-token>http://stub/sync/{STATE['sync_epoch']}</d:sync-token>",
            ))
            return

        if "calendar-query" in body or "addressbook-query" in body:
            members = [
                item_props(h)
                for h in sorted(STATE["items"]) if collection_of(h) == path
            ]
            self._send(207, multistatus(*members))
            return

        if "multiget" in body:
            hrefs = [
                h.split("</d:href>")[0]
                for h in body.split("<d:href>")[1:]
            ]
            members = [item_props(h.strip(), include_data=True) for h in hrefs]
            self._send(207, multistatus(*members))
            return

        self._send(501, "<html>unsupported report</html>", "text/html")

    def do_GET(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        item = STATE["items"].get(self.path)
        if item is None:
            self._send(404, "not found\n", "text/plain")
            return
        ctype = "text/calendar" if self.path.endswith(".ics") else "text/vcard"
        self._send(200, item["body"], ctype, etag=item["etag"])

    def do_POST(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        self._send(405, "<html>method not allowed</html>", "text/html")

    def do_PUT(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        body = self._read_body().decode(errors="replace")
        existing = STATE["items"].get(self.path)

        if_none = self.headers.get("If-None-Match")
        if_match = self.headers.get("If-Match")
        if if_none == "*" and existing is not None:
            self._send(412, "<html>exists</html>", "text/html")
            return
        if if_match:
            wanted = if_match.strip().strip('"')
            have = (existing or {}).get("etag", "").strip('"')
            if existing is None or wanted != have:
                self._send(412, "<html>etag mismatch</html>", "text/html")
                return
        etag = self._store(self.path, body)
        self._send(201 if existing is None else 204, b"", etag=etag)

    def do_DELETE(self):
        if self.path.startswith("/__control/"):
            self._control()
            return
        if not self._gate():
            return
        existing = STATE["items"].get(self.path)
        if existing is None:
            self._send(404, "not found\n", "text/plain")
            return
        if_match = self.headers.get("If-Match")
        if if_match and if_match.strip().strip('"') != existing["etag"].strip('"'):
            self._send(412, "<html>etag mismatch</html>", "text/html")
            return
        del STATE["items"][self.path]
        STATE["sync_epoch"] += 1
        self._send(204)

    # -- helpers ------------------------------------------------------------

    def _store(self, href, body):
        STATE["sync_epoch"] += 1
        etag = f'"stub-{STATE["sync_epoch"]}-{int(time.time()*1000)}"'
        STATE["items"][href] = {"body": body, "etag": etag}
        return etag


def _epoch_of(token):
    try:
        return int(token.rstrip("/").split("/")[-1])
    except (ValueError, IndexError):
        return -1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8643)
    parser.add_argument("--auth", help="user:pass — require HTTP Basic")
    parser.add_argument("--seed", type=Path, help="dir of .ics/.vcf seed files")
    parser.add_argument("--log", type=Path, help="append request log here")
    args = parser.parse_args()

    if args.auth:
        user, _, pw = args.auth.partition(":")
        STATE["auth"] = (user, pw)

    if args.seed:
        for f in sorted(args.seed.iterdir()):
            if f.suffix == ".ics":
                href = f"/cal/u/main/{f.name}"
            elif f.suffix == ".vcf":
                href = f"/card/u/main/{f.name}"
            else:
                continue
            STATE["items"][href] = {
                "body": f.read_text(),
                "etag": f'"seed-{f.stem}"',
            }

    if args.log:
        original = log_line
        fh = open(args.log, "a", buffering=1)

        def both(line):
            original(line)
            fh.write(line + "\n")

        globals()["log_line"] = both

    server = ThreadingHTTPServer(("127.0.0.1", args.port), StubDAV)
    print(f"stub-dav listening on http://127.0.0.1:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
