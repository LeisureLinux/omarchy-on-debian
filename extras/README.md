# extras/clock-zh — Chinese lunar clock

`Model.js` here is a **full replacement** for
`shell/plugins/panels/clock/Model.js`: upstream's model plus the lunar tables
and label functions that `patches/003` and `patches/004` call.

Because it is a replacement rather than a diff, regenerate it deliberately
after an upstream update — do not blindly re-copy over newer upstream code.

## Contents

- `lunarInfo` — 200 entries, 1900–2099, classic 17-bit packing
- `termInfo` — 200 rows × 24 solar terms, `(month << 5) | day`, 1-based month
- `solarToLunar`, `lunarYearName`, `lunarDayLabel`, `lunarFullLabel`
- `solarTerm`, `festivalLabel`, `localizeMonthNames`

## Regenerating the tables

```bash
pip install lunardate sxtwl
python3 gen-lunar-table.py > /tmp/lunarInfo.js   # self-verifies 1900-2099
python3 gen-term-table.py  > /tmp/termInfo.js    # 寿星天文历, ~1 min
```

Splice the output into `Model.js` (replace the existing `var … = [` block).
Sanity-check afterwards:

```bash
python3 - <<'EOF'
import sxtwl, datetime, re
js = open("Model.js").read()
rows = [r.strip().strip("[]") for r in
        re.search(r"var termInfo = \[(.*?)\n\]\n", js, re.S).group(1).strip().rstrip(",").split("],")]
# spot-check a few years against sxtwl here
EOF
```

## Display priority

1. Festival (元旦 / 春节 / 除夕 / 国庆 …)
2. Solar term (立春 … 冬至)
3. Lunar day, or the month name on the 1st (`七月`, `闰七月`)

## Traps

- **QML months are 0-based, the tables are 1-based.** Both `solarTerm()` and
  `solarFestivals` lookups must use `month + 1`. Get this wrong and every solar
  term is off by roughly a month (白露 shows up as 立秋).
- 除夕 is the last day of the lunar year. In a year with a leap 12th month, the
  year actually ends in the leap month — guard with
  `lunarLeapMonth(year) !== 12`.
- Lunar festivals are skipped in leap months (`lunar.isLeap`).
