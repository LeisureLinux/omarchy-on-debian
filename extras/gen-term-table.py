#!/usr/bin/env python3
"""Generate the termInfo table used by shell/plugins/panels/clock/Model.js.

One row per solar year (1900-2099), 24 entries, order starts at 小寒 (the
first term of a solar year). Each value packs (month << 5) | day with a
1-based month, so QML callers passing 0-based months must add 1.

Requires: pip install sxtwl   (寿星天文历 — the authoritative Chinese
ephemeris; do not approximate solar terms with a fixed formula)
"""
import datetime
import sys

JIEQI = ("冬至小寒大寒立春雨水惊蛰春分清明谷雨立夏小满芒种夏至小暑大暑"
         "立秋处暑白露秋分寒露霜降立冬小雪大雪")
# 小寒 first, matching the order the JS side expects.
ORDER = ("小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满",
         "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
         "立冬", "小雪", "大雪", "冬至")
START, END = 1900, 2099


def main():
    try:
        import sxtwl
    except ImportError:
        sys.exit("pip install sxtwl")

    for year in range(START, END + 1):
        found = {}
        d = datetime.date(year, 1, 1)
        while d.year == year:
            day = sxtwl.fromSolar(year, d.month, d.day)
            if day.hasJieQi():
                name = JIEQI[day.getJieQi() * 2:day.getJieQi() * 2 + 2]
                found.setdefault(name, (d.month, d.day))
            d += datetime.timedelta(days=1)
        values = []
        for name in ORDER:
            month, day = found[name]
            values.append(str((month << 5) | day))
        print("[" + ",".join(values) + "],")


if __name__ == "__main__":
    main()
