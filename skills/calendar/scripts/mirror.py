#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["google-api-python-client", "google-auth", "caldav", "icalendar", "tzdata"]
# ///
"""Publish your calendars to Google twice, one way, idempotently.

    busy   Every real commitment from every allowlisted calendar becomes an opaque
           "<Your Name> - Busy" block on a shared availability calendar. Titles, notes,
           locations and attendees never cross over. Share it with your team.
    copy   The iCloud calendars, full detail (titles, notes, locations, all-day events), on a
           private Google calendar, so you can toggle your Apple Calendar on inside Google
           Calendar. Never share it.

Both target calendars are owned by the service account, which grants your own account access.
Nothing reads back: an edit made on a target is overwritten on the next sync.

    mirror.py bootstrap                          # create both calendars, apply the ACLs, print ids
    mirror.py share <email> [--scope group]      # give a person or a Google Group read access to `busy`
    mirror.py sync                               # both targets, rolling window (what the timer runs)
    mirror.py sync --only busy --from 2026-09-21 --to 2026-09-27 --dry-run
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import sys

from googleapiclient.errors import HttpError

import calendars as src

TZ = src.TZ
CFG = src.CFG
BUSY = CFG["availability"]
COPY = CFG.get("private_copy")
PAST_DAYS = CFG.get("past_days", 14)
FUTURE_DAYS = CFG.get("future_days", 120)
# Only these calendars publish busy time. An allowlist, so a calendar added later stays private
# until you name it. Never include another availability calendar: teammates' calendars that
# sync down into yours would republish THEIR time under your name.
PUBLISH = set(BUSY.get("publish_calendars") or (*src.ICLOUD_CALENDARS, *src.GOOGLE_CALENDARS))
SKIP_EXACT = {t.lower() for t in BUSY.get("skip_titles", [])}
SKIP_PREFIXES = tuple(p.lower() for p in BUSY.get("skip_prefixes", []))


def stable_id(payload: str) -> str:
    """Google event ids allow base32hex; a hash makes every sync land on the same id."""
    return base64.b32hexencode(hashlib.sha1(payload.encode()).digest()).decode().rstrip("=").lower()


def parse_ts(value: str) -> dt.datetime:
    stamp = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return stamp.replace(tzinfo=TZ) if stamp.tzinfo is None else stamp.astimezone(TZ)


# MARK: what each target should hold

def busy_bodies(events: list[dict]) -> dict[str, dict]:
    """Real commitments -> merged opaque blocks, keyed by a hash of start, end and title."""
    spans = []
    for ev in events:
        title = (ev.get("title") or "").strip().lower()
        if ev.get("calendar") not in PUBLISH or ev.get("all_day"):
            continue  # an all-day event is a marker; publishing it would black out the day
        if title in SKIP_EXACT or title.startswith(SKIP_PREFIXES):
            continue
        begins, finishes = parse_ts(ev["start"]), parse_ts(ev["end"])
        if finishes > begins:
            spans.append((begins, finishes))
    merged: list[list[dt.datetime]] = []
    for begins, finishes in sorted(spans):  # touching or overlapping spans become one block
        if merged and begins <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], finishes)
        else:
            merged.append([begins, finishes])
    out = {}
    for begins, finishes in merged:
        key = stable_id(f"{begins.isoformat()}|{finishes.isoformat()}|{BUSY['busy_title']}")
        out[key] = {
            "id": key, "summary": BUSY["busy_title"], "transparency": "opaque",
            "start": {"dateTime": begins.isoformat(), "timeZone": str(TZ)},
            "end": {"dateTime": finishes.isoformat(), "timeZone": str(TZ)},
            "reminders": {"useDefault": False, "overrides": []},
        }
    return out


def copy_bodies(events: list[dict]) -> dict[str, dict]:
    """Full-detail copies, keyed by a hash of every visible field, so an edit replaces the copy."""
    colors = COPY.get("colors", {})
    out = {}
    for ev in events:
        if ev.get("all_day"):
            first = dt.date.fromisoformat(ev["start"][:10])
            last = dt.date.fromisoformat(ev["end"][:10])
            start = {"date": first.isoformat()}
            end = {"date": max(last, first + dt.timedelta(days=1)).isoformat()}  # Google's end is exclusive
        else:
            start = {"dateTime": parse_ts(ev["start"]).isoformat(), "timeZone": str(TZ)}
            end = {"dateTime": parse_ts(ev["end"]).isoformat(), "timeZone": str(TZ)}
        body = {
            "summary": ev.get("title") or "(untitled)", "start": start, "end": end,
            "description": "\n\n".join(filter(None, [ev.get("notes"), f"Calendar: {ev['calendar']}"])),
            "reminders": {"useDefault": False, "overrides": []},
        }
        if ev.get("location"):
            body["location"] = ev["location"]
        if ev["calendar"] in colors:
            body["colorId"] = colors[ev["calendar"]]
        body["id"] = stable_id(json.dumps(body, sort_keys=True))
        out[body["id"]] = body
    return out


# MARK: Google plumbing

def find_calendar(svc, name: str) -> str | None:
    """By real title (calendars.summary). Rename the calendar and the config together, or
    bootstrap creates a duplicate nobody is subscribed to."""
    for entry in svc.calendarList().list().execute().get("items", []):
        if entry.get("summary") == name:
            return entry["id"]
    return None


def apply(svc, cal: str, desired: dict[str, dict], first: dt.date, last: dt.date, dry: bool) -> str:
    """Make `cal` hold exactly `desired` inside [first, last]. Deletion is scoped to that window."""
    lo, hi = src.window(first, last)
    existing, page = {}, None
    while True:
        resp = svc.events().list(calendarId=cal, timeMin=lo.isoformat(), timeMax=hi.isoformat(),
                                 singleEvents=True, pageToken=page).execute()
        existing.update({ev["id"]: ev for ev in resp.get("items", [])})
        if not (page := resp.get("nextPageToken")):
            break
    added = sorted(set(desired) - set(existing))
    stale = sorted(set(existing) - set(desired))
    if dry:
        for key in added:
            print(f"+ {desired[key]['start'].get('dateTime') or desired[key]['start']['date']}  {desired[key]['summary']}")
        for key in stale:
            print(f"- {existing[key]['start'].get('dateTime') or existing[key]['start'].get('date')}  {existing[key].get('summary')}")
    else:
        for key in added:
            try:
                svc.events().insert(calendarId=cal, body=desired[key]).execute()
            except HttpError as err:
                if err.resp.status != 409:  # 409: the id is in Google's trash or a parallel run wrote it
                    raise
                svc.events().update(calendarId=cal, eventId=key, body=desired[key]).execute()
        for key in stale:
            try:
                svc.events().delete(calendarId=cal, eventId=key).execute()
            except HttpError as err:
                if err.resp.status not in (404, 410):  # already gone: a parallel run removed it
                    raise
    return f"+{len(added)} -{len(stale)} ={len(desired) - len(added)}"


# MARK: commands

def targets():
    yield "busy", BUSY, busy_bodies, None
    if COPY:
        yield "copy", COPY, copy_bodies, src.ICLOUD_CALENDARS


def sync(args) -> None:
    svc = src.google_service()
    today = dt.datetime.now(TZ).date()
    first = dt.date.fromisoformat(args.start) if args.start else today - dt.timedelta(days=PAST_DAYS)
    last = dt.date.fromisoformat(args.end) if args.end else today + dt.timedelta(days=FUTURE_DAYS)
    failed = False
    for label, conf, build, names in targets():
        if args.only and args.only != label:
            continue
        try:
            # Never sync from a partial read: stale deletion would erase real time.
            events = src.read(first, last, names)
        except src.CalendarError as err:
            print(f"{label}: not syncing: {err}", file=sys.stderr)
            failed = True
            continue
        cal = find_calendar(svc, conf["calendar_name"])
        if not cal:
            sys.exit(f"no calendar named {conf['calendar_name']!r}; run `mirror.py bootstrap` first")
        print(f"{label}: {first} to {last}: {apply(svc, cal, build(events), first, last, args.dry_run)}")
    sys.exit(1 if failed else 0)


def bootstrap(args) -> None:
    """Create each target calendar if missing and apply its grants. Safe to re-run."""
    svc = src.google_service()
    for label, conf, _, _ in targets():
        cid = find_calendar(svc, conf["calendar_name"])
        if not cid:
            cid = svc.calendars().insert(body={"summary": conf["calendar_name"], "timeZone": str(TZ),
                                               "description": "Generated mirror. Edit the source calendar."}).execute()["id"]
            print(f"{label}: created {cid}")
        else:
            print(f"{label}: exists {cid}")
        have = {r["scope"].get("value"): r["role"] for r in svc.acl().list(calendarId=cid).execute().get("items", [])}
        for email, role in conf.get("access", {}).items():
            if have.get(email) != role:
                svc.acl().insert(calendarId=cid, body={"role": role, "scope": {"type": "user", "value": email}}).execute()
                print(f"{label}: granted {role} to {email} (accept the emailed invite to see it)")


def share(args) -> None:
    """Read access to `busy` for a person or a Google Group. The scope type must match the
    address kind: a group address sent as `user` is accepted and silently grants nobody."""
    svc = src.google_service()
    cid = find_calendar(svc, BUSY["calendar_name"]) or sys.exit("run `mirror.py bootstrap` first")
    svc.acl().insert(calendarId=cid, body={"role": args.role, "scope": {"type": args.scope, "value": args.email}}).execute()
    print(f"shared {BUSY['calendar_name']} with {args.scope} {args.email} as {args.role}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subs = parser.add_subparsers(dest="cmd", required=True)
    subs.add_parser("bootstrap").set_defaults(fn=bootstrap)
    sh = subs.add_parser("share")
    sh.add_argument("email")
    sh.add_argument("--role", default="reader", choices=["freeBusyReader", "reader"])
    sh.add_argument("--scope", default="user", choices=["user", "group", "domain"])
    sh.set_defaults(fn=share)
    sy = subs.add_parser("sync")
    sy.add_argument("--from", dest="start", metavar="YYYY-MM-DD", help=f"default: today - {PAST_DAYS} days")
    sy.add_argument("--to", dest="end", metavar="YYYY-MM-DD", help=f"default: today + {FUTURE_DAYS} days")
    sy.add_argument("--only", choices=["busy", "copy"])
    sy.add_argument("--dry-run", action="store_true")
    sy.set_defaults(fn=sync)
    args = parser.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
