# -*- coding: utf-8 -*-
"""
Opening-hours tests.

The cases that matter are the ones that decide whether a real customer can
check out: a branch nobody has configured yet, a shop that closes after
midnight, and the legacy single-window shape that every existing branch is
still stored in.

    DJANGO_SETTINGS_MODULE=config.settings_test python manage.py test apps.branches
"""
import datetime

from django.test import TestCase

from .hours import is_open_at, schedule_of
from .models import Branch
from apps.stores.models import Store


def at(year, month, day, hour, minute=0):
    return datetime.datetime(year, month, day, hour, minute)


# 2026-08-10 is a Monday, so weekday() == 0 and the keys line up with the
# schedule dictionaries below without arithmetic in the test.
MONDAY = (2026, 8, 10)
TUESDAY = (2026, 8, 11)
FRIDAY = (2026, 8, 14)


class HoursTests(TestCase):

    def setUp(self):
        self.store = Store.objects.create(name_ar='متجر', name_en='Store', type='supermarket')

    def branch(self, **kwargs):
        return Branch.objects.create(
            store=self.store, name='Main', name_ar='الفرع الرئيسي', name_en='Main',
            address='...', latitude=27.9, longitude=34.3, phone='0100', **kwargs
        )

    def test_branch_with_no_hours_is_open(self):
        """Hours are opt-in — an unconfigured branch must not refuse orders."""
        b = self.branch()
        self.assertTrue(is_open_at(b, at(*MONDAY, 3)))
        self.assertTrue(is_open_at(b, at(*MONDAY, 15)))

    def test_per_day_window(self):
        b = self.branch(operating_hours={'schedule': {
            '0': {'open': '09:00', 'close': '17:00', 'closed': False},
            '4': {'open': '13:00', 'close': '23:00', 'closed': False},
        }})
        self.assertFalse(is_open_at(b, at(*MONDAY, 8, 59)))
        self.assertTrue(is_open_at(b, at(*MONDAY, 9)))
        self.assertTrue(is_open_at(b, at(*MONDAY, 16, 59)))
        self.assertFalse(is_open_at(b, at(*MONDAY, 17)))
        # Friday opens late, and that is a different day's window.
        self.assertFalse(is_open_at(b, at(*FRIDAY, 12)))
        self.assertTrue(is_open_at(b, at(*FRIDAY, 14)))

    def test_closed_day(self):
        b = self.branch(operating_hours={'schedule': {
            '0': {'open': '09:00', 'close': '17:00', 'closed': True},
        }})
        self.assertFalse(is_open_at(b, at(*MONDAY, 12)))

    def test_window_past_midnight_stays_open_into_the_next_day(self):
        b = self.branch(operating_hours={'schedule': {
            '0': {'open': '17:00', 'close': '02:00', 'closed': False},
            '1': {'open': '17:00', 'close': '02:00', 'closed': False},
        }})
        self.assertTrue(is_open_at(b, at(*MONDAY, 23)))
        self.assertTrue(is_open_at(b, at(*TUESDAY, 1)))    # Monday's shift
        self.assertFalse(is_open_at(b, at(*TUESDAY, 3)))
        self.assertFalse(is_open_at(b, at(*TUESDAY, 12)))

    def test_equal_open_and_close_is_open_all_day(self):
        b = self.branch(operating_hours={'schedule': {
            '0': {'open': '00:00', 'close': '00:00', 'closed': False},
        }})
        self.assertTrue(is_open_at(b, at(*MONDAY, 4)))

    def test_legacy_single_window_is_still_honoured(self):
        """Existing branches were saved before per-day hours existed."""
        b = self.branch(operating_hours={'open': '08:00', 'close': '23:00',
                                         'days': [1, 2, 3, 4, 5, 6, 7]})
        self.assertTrue(is_open_at(b, at(*MONDAY, 10)))
        self.assertFalse(is_open_at(b, at(*MONDAY, 7)))

    def test_legacy_day_list_can_close_a_day(self):
        # days are 1=Mon..7=Sun; Friday (5) is missing.
        b = self.branch(operating_hours={'open': '08:00', 'close': '23:00',
                                         'days': [1, 2, 3, 4, 6, 7]})
        self.assertTrue(is_open_at(b, at(*MONDAY, 10)))
        self.assertFalse(is_open_at(b, at(*FRIDAY, 10)))

    def test_legacy_opening_time_columns_are_read(self):
        b = self.branch(opening_time=datetime.time(9, 0), closing_time=datetime.time(21, 0))
        self.assertTrue(is_open_at(b, at(*MONDAY, 10)))
        self.assertFalse(is_open_at(b, at(*MONDAY, 22)))

    def test_schedule_always_returns_seven_days(self):
        b = self.branch(operating_hours={'schedule': {'0': {'open': '09:00', 'close': '17:00'}}})
        self.assertEqual(sorted(schedule_of(b).keys()), ['0', '1', '2', '3', '4', '5', '6'])
