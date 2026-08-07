# -*- coding: utf-8 -*-
"""
Opening hours for a branch: a from–to window per weekday.

`Branch.operating_hours` used to hold one window shared by every day
(`{"open": "09:00", "close": "23:00", "days": [1..7]}`), which cannot say
"Friday opens late". The stored shape is now keyed by weekday:

    {"schedule": {"0": {"open": "09:00", "close": "23:00", "closed": false},
                  ...
                  "6": {"open": "13:00", "close": "23:00", "closed": false}}}

Keys are Python weekdays — Monday is 0, Sunday is 6 — because that is what
`datetime.weekday()` returns and translating once here beats translating at
every call site.

Both older shapes are still read, so a branch that was never re-saved keeps the
hours it had rather than falling back to "closed" and refusing every order.
"""
from datetime import time

DAY_KEYS = ['0', '1', '2', '3', '4', '5', '6']

# Arabic day names, indexed by Python weekday, for the messages the customer
# actually sees.
DAY_NAMES_AR = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد']

CLOSED_AR = 'المتجر مغلق حالياً'
CLOSED_EN = 'The store is closed right now'


def _parse_hhmm(value):
    """'09:30' → time(9, 30). None for anything unparseable."""
    if isinstance(value, time):
        return value
    if not value or not isinstance(value, str):
        return None
    parts = value.strip().split(':')
    if len(parts) < 2:
        return None
    try:
        hour, minute = int(parts[0]), int(parts[1])
    except (TypeError, ValueError):
        return None
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    return time(hour, minute)


def _day_entry(open_value, close_value, closed=False):
    return {
        'open': open_value if isinstance(open_value, str) else '',
        'close': close_value if isinstance(close_value, str) else '',
        'closed': bool(closed),
    }


def schedule_of(branch):
    """The seven-day schedule for this branch, whatever shape it is stored in.

    Returns {weekday_key: {'open', 'close', 'closed'}} for all seven days.
    """
    raw = getattr(branch, 'operating_hours', None) or {}

    # Current shape.
    stored = raw.get('schedule') if isinstance(raw, dict) else None
    if isinstance(stored, dict) and stored:
        return {
            key: _day_entry(
                (stored.get(key) or {}).get('open'),
                (stored.get(key) or {}).get('close'),
                (stored.get(key) or {}).get('closed', False),
            )
            for key in DAY_KEYS
        }

    # Legacy: one window, optionally limited to some days (1=Mon..7=Sun).
    legacy_open = raw.get('open') if isinstance(raw, dict) else None
    legacy_close = raw.get('close') if isinstance(raw, dict) else None
    if not legacy_open and getattr(branch, 'opening_time', None):
        legacy_open = branch.opening_time.strftime('%H:%M')
    if not legacy_close and getattr(branch, 'closing_time', None):
        legacy_close = branch.closing_time.strftime('%H:%M')

    legacy_days = raw.get('days') if isinstance(raw, dict) else None
    open_weekdays = None
    if isinstance(legacy_days, list) and legacy_days:
        open_weekdays = {int(d) - 1 for d in legacy_days if str(d).isdigit()}

    return {
        key: _day_entry(
            legacy_open, legacy_close,
            closed=open_weekdays is not None and int(key) not in open_weekdays,
        )
        for key in DAY_KEYS
    }


def is_open_at(branch, when):
    """Is this branch open at `when` (a local datetime)?

    A branch with no hours configured is open — hours are opt-in, and treating
    "not set up yet" as closed would refuse every order the moment this shipped.
    A window whose close time is at or before its open time is read as running
    past midnight (23:00–02:00), which is what a late-night grocer means.
    """
    schedule = schedule_of(branch)
    today = schedule.get(str(when.weekday())) or {}
    now = when.time()

    def window_covers(entry, moment):
        if not entry or entry.get('closed'):
            return False
        opens = _parse_hhmm(entry.get('open'))
        closes = _parse_hhmm(entry.get('close'))
        if not opens or not closes:
            return None  # nothing configured for this day
        if opens < closes:
            return opens <= moment < closes
        if opens == closes:
            return True  # a full 24 hours
        return moment >= opens or moment < closes  # spans midnight

    covered = window_covers(today, now)
    if covered:
        return True

    # Before deciding "closed", let yesterday's overnight window reach into
    # today — at 01:00 on Tuesday the relevant shift is Monday's 23:00–02:00.
    yesterday = schedule.get(str((when.weekday() - 1) % 7)) or {}
    opens = _parse_hhmm(yesterday.get('open'))
    closes = _parse_hhmm(yesterday.get('close'))
    if (not yesterday.get('closed') and opens and closes
            and opens > closes and now < closes):
        return True

    if covered is None and window_covers(yesterday, now) is None:
        # Neither day has usable times: hours were never configured.
        return True
    return False


def hours_message(branch, when):
    """Arabic + English 'we are closed, we open at ...' text for a refusal."""
    schedule = schedule_of(branch)
    today = schedule.get(str(when.weekday())) or {}
    if today.get('closed') or not today.get('open'):
        return f'{CLOSED_AR} — {CLOSED_EN}'
    return (f'{CLOSED_AR}. مواعيد {DAY_NAMES_AR[when.weekday()]}: '
            f'{today.get("open")} - {today.get("close")}')
