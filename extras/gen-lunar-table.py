#!/usr/bin/env python3
"""Generate the lunarInfo table used by shell/plugins/panels/clock/Model.js.

Packing (classic 17-bit layout — bit order matters):
    bit 16        leap month has 30 days
    bits 15..4    months 1..12, 1 = big (30 days)
    bits 3..0     leap month number (0 = no leap month)

Requires: pip install lunardate

lunardate carries this table as YEAR_INFOS (1900-2099) in exactly this format,
so this script re-emits it and verifies every month length against lunardate's
own conversion engine.

Gotchas learned the hard way:
  * LunarDate.__init__ does NOT validate — day 30 of a 29-day month constructs
    fine and only blows up in to_solar_date(). Validate by converting.
  * Do not derive month lengths from consecutive first-of-month solar dates:
    in a year with a leap month (1900 has 闰八月) the regular month then
    measures ~59 days. Use the leap flag to order the sequence, or ask
    lunardate directly.
"""
import sys

try:
    from lunardate import LunarDate, YEAR_INFOS
except ImportError:
    sys.exit("pip install lunardate")

if len(YEAR_INFOS) != 200:
    sys.exit(f"unexpected table size: {len(YEAR_INFOS)} (expected 200)")


def month_length(year, month, is_leap_month=False):
    """30 or 29. Validation happens in to_solar_date, not in the constructor."""
    try:
        LunarDate(year, month, 30, is_leap_month=is_leap_month).to_solar_date()
        return 30
    except ValueError:
        return 29


for year in range(1900, 2100):
    info = YEAR_INFOS[year - 1900]
    leap = info & 0xF
    for month in range(1, 13):
        declared = 30 if info & (0x10000 >> month) else 29
        actual = month_length(year, month)
        if declared != actual:
            sys.exit(f"table mismatch: {year} month {month} declared={declared} actual={actual}")
    if leap:
        declared = 30 if info & 0x10000 else 29
        actual = month_length(year, leap, is_leap_month=True)
        if declared != actual:
            sys.exit(f"table mismatch: {year} leap month {leap} declared={declared} actual={actual}")

print("var lunarInfo = [", end="")
values = [f"{v:#x}" for v in YEAR_INFOS]
for i in range(0, len(values), 16):
    print()
    print(",".join(values[i:i + 16]) + ("," if i + 16 < len(values) else ""), end="")
print("\n]")
