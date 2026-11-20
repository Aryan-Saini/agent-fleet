"""Your calendars straight from iCloud and Google, on any machine. Shared by `cal` and `mirror.py`.

Events come back as dicts: `id`, `title`, `calendar`, `date`, `start`, `end`, `all_day`, and
optional `location`, `notes`. Times are local wall-clock `YYYY-MM-DDTHH:MM` in the configured
time zone.

- iCloud over CalDAV, read AND write, with an app-specific password.
- Google read-only, through a service account that holds a `reader` share on each Google
  calendar you list. Nothing here writes a Google source calendar.

Everything personal lives in CONFIG (default ~/.config/calendar-mirror/config.json, override
with $CALENDAR_MIRROR_CONFIG). See config.example.json next to this file.

Ids are `<calendar>:<uid>`, so a write never has to search every calendar. An occurrence of a
recurring series gets `<calendar>:<uid>#<recurrence stamp>` and is read-only here; edit series
in Calendar.app.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import uuid
import zoneinfo

CONFIG = pathlib.Path(os.environ.get("CALENDAR_MIRROR_CONFIG", "~/.config/calendar-mirror/config.json")).expanduser()
ICLOUD_URL = "https://caldav.icloud.com/"


class CalendarError(Exception):
    """A calendar source failed: credentials, network, an unshared calendar. User-facing."""


class Refused(CalendarError):
    """The request itself was refused (bad id, read-only target, recurring series)."""


def _load_config() -> dict:
    if not CONFIG.exists():
        raise SystemExit(f"missing config: {CONFIG} (copy config.example.json there and fill it in)")
    return json.loads(CONFIG.read_text())


CFG = _load_config()

# Time zone rules come from the `tzdata` package in each script's inline dependencies, never the
# host. A stale host database applies old DST rules and shifts every block after the change by
# an hour, which churns hundreds of mirror events in one run.
zoneinfo.reset_tzpath([])
TZ = zoneinfo.ZoneInfo(CFG["timezone"])
ICLOUD_CREDS = pathlib.Path(CFG.get("icloud_credentials", "~/.config/icloud/caldav.json")).expanduser()
GOOGLE_KEY = pathlib.Path(CFG["google_service_account_key"]).expanduser()
ICLOUD_CALENDARS: tuple[str, ...] = tuple(CFG.get("icloud_calendars", []))
# Display name (what you call it) -> Google calendar id (usually the account's email).
GOOGLE_CALENDARS: dict[str, str] = dict(CFG.get("google_calendars", {}))
# Invites you declined on these addresses are not commitments.
SELF_ADDRESSES = set(CFG.get("self_addresses", []))


def window(first: dt.date, last: dt.date) -> tuple[dt.datetime, dt.datetime]:
    """[first 00:00, last+1 00:00) local: both dates inclusive."""
    return (dt.datetime.combine(first, dt.time.min, TZ),
            dt.datetime.combine(last + dt.timedelta(days=1), dt.time.min, TZ))


def _local(value: dt.date | dt.datetime) -> tuple[str, bool]:
    """(`YYYY-MM-DDTHH:MM` local wall-clock, all_day)."""
    if not isinstance(value, dt.datetime):
        return f"{value.isoformat()}T00:00", True
    if value.tzinfo is None:
        value = value.replace(tzinfo=TZ)
    return value.astimezone(TZ).strftime("%Y-%m-%dT%H:%M"), False


# MARK: iCloud

_icloud_cache: dict[str, object] | None = None


def icloud_calendars() -> dict[str, object]:
    """Name -> caldav.Calendar for the configured iCloud calendars, one login per process."""
    global _icloud_cache
    if _icloud_cache is None:
        import caldav

        if not ICLOUD_CREDS.exists():
            raise CalendarError(f"missing iCloud credentials: {ICLOUD_CREDS}")
        creds = json.loads(ICLOUD_CREDS.read_text())
        client = caldav.DAVClient(url=ICLOUD_URL, username=creds["username"], password=creds["password"])
        by_name = {c.name: c for c in client.principal().calendars()}
        missing = [n for n in ICLOUD_CALENDARS if n not in by_name]
        if missing:
            raise CalendarError(f"iCloud calendars not found: {missing} (have {sorted(by_name)})")
        _icloud_cache = {n: by_name[n] for n in ICLOUD_CALENDARS}
    return _icloud_cache


def _describe_vevent(comp, calendar: str) -> dict:
    begins = comp.decoded("DTSTART")
    if "DTEND" in comp:
        finishes = comp.decoded("DTEND")
    elif "DURATION" in comp:
        finishes = begins + comp.decoded("DURATION")
    else:
        finishes = begins
    start, all_day = _local(begins)
    end, _ = _local(finishes)
    ident = f"{calendar}:{comp.get('UID')}"
    if "RECURRENCE-ID" in comp:
        ident += "#" + _local(comp.decoded("RECURRENCE-ID"))[0]
    ev = {"id": ident, "title": str(comp.get("SUMMARY", "")), "calendar": calendar,
          "date": start[:10], "start": start, "end": end, "all_day": all_day}
    for field, key in (("LOCATION", "location"), ("DESCRIPTION", "notes")):
        if comp.get(field):
            ev[key] = str(comp.get(field))
    return ev


def read_icloud(names, start: dt.datetime, end: dt.datetime) -> list[dict]:
    if not names:
        return []
    cals = icloud_calendars()
    events = []
    for name in names:
        # expand=True yields one entry per occurrence of a recurring series in the window.
        for item in cals[name].search(start=start, end=end, event=True, expand=True):
            for comp in item.icalendar_instance.walk("VEVENT"):
                events.append(_describe_vevent(comp, name))
    return events


def _split_id(ident: str) -> tuple[str, str]:
    calendar, _, uid = ident.partition(":")
    if calendar not in ICLOUD_CALENDARS or not uid:
        raise Refused(f"not a writable event id: {ident} (want <iCloud calendar>:<uid>)")
    if "#" in uid:
        raise Refused(f"{ident} is one occurrence of a recurring series; edit series in Calendar.app")
    return calendar, uid


def _fetch(ident: str):
    calendar, uid = _split_id(ident)
    cal = icloud_calendars()[calendar]
    try:
        obj = cal.event_by_uid(uid)
    except Exception:
        # iCloud answers the UID-filter REPORT with 412 for some events; they still live at
        # <uid>.ics, so load that directly and check the UID.
        try:
            obj = cal.event_by_url(cal.url.join(f"{uid}.ics"))
            obj.load()
            if str(obj.icalendar_instance.walk("VEVENT")[0]["uid"]) != uid:
                raise LookupError(uid)
        except Exception as exc:  # caldav raises its own NotFoundError
            raise Refused(f"no event with id {ident}") from exc
    comp = obj.icalendar_instance.walk("VEVENT")
    if comp and "RRULE" in comp[0]:
        raise Refused(f"{ident} is a recurring series; edit it in Calendar.app")
    return obj


def add_icloud(calendar: str, events: list[dict]) -> list[dict]:
    """Create single events: each needs title, date, start, end (local HH:MM)."""
    import icalendar

    if calendar not in ICLOUD_CALENDARS:
        raise Refused(f"{calendar!r} is not writable (writable: {', '.join(ICLOUD_CALENDARS)})")
    target = icloud_calendars()[calendar]
    created = []
    for ev in events:
        try:
            title, date, start, end = ev["title"], ev["date"], ev["start"], ev["end"]
        except KeyError as exc:
            raise Refused("each event needs title, date, start, end") from exc
        if start == end:
            raise Refused(f'zero-length event "{title}" on {date} (start == end)')
        begins = dt.datetime.fromisoformat(f"{date}T{start}").replace(tzinfo=TZ)
        finishes = dt.datetime.fromisoformat(f"{date}T{end}").replace(tzinfo=TZ)
        if finishes < begins:  # strictly earlier means overnight; equal is rejected above
            finishes += dt.timedelta(days=1)

        vevent = icalendar.Event()
        vevent.add("uid", f"{uuid.uuid4()}@calendar-skill")
        vevent.add("dtstamp", dt.datetime.now(dt.timezone.utc))
        # UTC instants: no VTIMEZONE to get wrong.
        vevent.add("dtstart", begins.astimezone(dt.timezone.utc))
        vevent.add("dtend", finishes.astimezone(dt.timezone.utc))
        vevent.add("summary", title)
        if ev.get("location"):
            vevent.add("location", ev["location"])
        if ev.get("notes"):
            vevent.add("description", ev["notes"])
        wrapper = icalendar.Calendar()
        wrapper.add("prodid", "-//calendar-skill//cal//EN")
        wrapper.add("version", "2.0")
        wrapper.add_component(vevent)
        target.save_event(wrapper.to_ical().decode())
        created.append(_describe_vevent(vevent, calendar))
    return created


def delete_icloud(ids: list[str]) -> None:
    objs = [_fetch(i) for i in ids]  # resolve all first: nothing is deleted if one id is bad
    for obj in objs:
        obj.delete()


def move_icloud(ids: list[str], calendar: str) -> list[dict]:
    """Same UID, same data, new calendar. CalDAV has no cross-calendar move, and iCloud rejects
    a UID that still exists in another calendar (412), so delete first, then save. If the save
    fails, the event goes back to its original calendar."""
    if calendar not in ICLOUD_CALENDARS:
        raise Refused(f"{calendar!r} is not writable (writable: {', '.join(ICLOUD_CALENDARS)})")
    target = icloud_calendars()[calendar]
    objs = [(_fetch(i), i) for i in ids]
    moved = []
    for obj, ident in objs:
        if ident.partition(":")[0] == calendar:
            continue
        data = obj.data
        source = icloud_calendars()[ident.partition(":")[0]]
        obj.delete()
        try:
            target.save_event(data)
        except Exception:
            source.save_event(data)
            raise
        moved.extend(_describe_vevent(c, calendar) for c in obj.icalendar_instance.walk("VEVENT"))
    return moved


# MARK: Google

_google_svc = None


def google_service():
    """Calendar client for the service account acting as itself. No impersonation."""
    global _google_svc
    if _google_svc is None:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build

        if not GOOGLE_KEY.exists():
            raise CalendarError(f"missing service account key: {GOOGLE_KEY}")
        creds = service_account.Credentials.from_service_account_file(
            str(GOOGLE_KEY), scopes=["https://www.googleapis.com/auth/calendar"])
        _google_svc = build("calendar", "v3", credentials=creds, cache_discovery=False)
    return _google_svc


def read_google(names, start: dt.datetime, end: dt.datetime) -> list[dict]:
    from googleapiclient.errors import HttpError

    if not names:
        return []
    svc = google_service()
    events = []
    for name in names:
        cid = GOOGLE_CALENDARS[name]
        page = None
        while True:
            try:
                resp = svc.events().list(calendarId=cid, timeMin=start.isoformat(), timeMax=end.isoformat(),
                                         singleEvents=True, pageToken=page).execute()
            except HttpError as exc:
                if exc.resp.status == 404:
                    raise CalendarError(f"{name} is not shared with the service account") from exc
                raise
            for ev in resp.get("items", []):
                # Cancelled, marked Free, or declined by you: not a commitment.
                if ev.get("status") == "cancelled" or ev.get("transparency") == "transparent":
                    continue
                if any(a.get("email") in SELF_ADDRESSES and a.get("responseStatus") == "declined"
                       for a in ev.get("attendees", [])):
                    continue
                all_day = "date" in ev["start"]
                if all_day:
                    s, e = f"{ev['start']['date']}T00:00", f"{ev['end']['date']}T00:00"
                else:
                    s = _local(dt.datetime.fromisoformat(ev["start"]["dateTime"]))[0]
                    e = _local(dt.datetime.fromisoformat(ev["end"]["dateTime"]))[0]
                out = {"id": f"{name}:{ev['id']}", "title": ev.get("summary", ""), "calendar": name,
                       "date": s[:10], "start": s, "end": e, "all_day": all_day}
                if ev.get("location"):
                    out["location"] = ev["location"]
                if ev.get("description"):
                    out["notes"] = ev["description"]
                events.append(out)
            page = resp.get("nextPageToken")
            if not page:
                break
    return events


# MARK: both

def calendars() -> list[dict]:
    return ([{"title": n, "source": "iCloud", "writable": True} for n in ICLOUD_CALENDARS]
            + [{"title": n, "source": "Google", "writable": False} for n in GOOGLE_CALENDARS])


def read(first: dt.date, last: dt.date, names=None) -> list[dict]:
    """Every event overlapping [first, last] on `names` (default: all). Raises on any failure,
    so a caller never mistakes an unreadable calendar for an empty one."""
    names = list(names) if names else list(ICLOUD_CALENDARS) + list(GOOGLE_CALENDARS)
    unknown = [n for n in names if n not in ICLOUD_CALENDARS and n not in GOOGLE_CALENDARS]
    if unknown:
        raise Refused(f"unknown calendar {unknown} (see: cal calendars)")
    start, end = window(first, last)
    events = (read_icloud([n for n in names if n in ICLOUD_CALENDARS], start, end)
              + read_google([n for n in names if n in GOOGLE_CALENDARS], start, end))
    return sorted(events, key=lambda e: (e["start"], e["calendar"], e["title"]))
