// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "dddd HH:mm:ss",
  "dddd h:mm:ss AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

// Whether a format prints seconds, so the widget can tick once a second only
// for the formats that show them. Quoted literals go first: the s in a 'Sat'
// is text rather than a token, and an opening quote with no closing one runs
// to the end of the format the way Qt reads it.
function clockNeedsSeconds(format) {
  var text = String(format === undefined || format === null ? "" : format)
  return /s/.test(text.replace(/'[^']*'?/g, ""))
}

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- 24 solar terms (节气), 1900-2099, one row per year, order 小寒..冬至,
//      each value packs (month << 5) | day. Generated from sxtwl (寿星天文历).
var termInfo = [
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,199,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,103,118,134,149,167,182,199,214,232,248,265,280,297,312,329,344,360,375,392,407],
[39,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,103,118,134,149,167,182,199,214,232,248,265,280,297,312,329,344,360,375,392,407],
[39,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,103,118,134,149,167,182,199,214,232,248,265,280,297,312,329,344,360,375,392,407],
[39,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,374,391,406],
[38,52,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,102,118,134,149,166,182,199,214,232,248,264,280,297,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,149,166,181,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,406],
[38,53,69,84,102,118,134,149,166,182,199,214,232,248,264,280,297,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,232,247,264,280,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,199,214,232,248,264,280,297,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,232,247,264,280,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,199,214,232,248,264,280,297,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,199,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,102,117,134,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,102,117,133,148,165,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,101,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,248,264,280,296,312,329,344,360,375,392,407],
[38,53,69,84,101,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,232,247,264,280,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,84,101,116,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,312,329,344,360,375,392,406],
[38,53,69,83,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,102,117,133,149,166,182,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,69,83,101,116,132,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,375,391,406],
[38,52,68,83,102,117,133,149,166,181,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,69,83,101,116,132,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,232,247,264,280,296,311,329,344,360,375,392,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,280,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,83,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,329,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,181,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,375,391,406],
[38,53,68,83,101,116,132,148,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,102,117,133,148,166,181,198,214,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,83,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,344,360,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,166,181,198,213,231,247,264,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,213,230,246,263,278,295,310,327,343,359,374,390,405],
[37,52,67,82,101,116,132,147,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,102,117,133,148,165,181,198,213,231,247,263,279,296,311,328,343,359,374,391,406],
[38,52,68,83,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,133,148,165,181,198,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,83,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,164,180,197,212,230,246,262,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,133,148,165,181,197,213,231,247,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,164,180,197,212,230,246,262,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,327,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,180,197,213,231,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,164,180,197,212,230,246,262,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,327,343,359,374,390,405],
[37,52,67,82,101,116,132,147,165,180,197,213,230,246,263,279,295,310,328,343,359,374,391,405],
[37,52,68,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,101,116,132,147,164,180,197,212,230,246,262,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,52,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,100,115,132,147,164,180,197,212,230,246,262,278,294,310,327,342,358,373,390,405],
[36,51,67,82,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,391,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,406],
[37,52,68,83,100,115,132,147,164,180,196,212,230,246,262,278,294,310,327,342,358,373,390,405],
[36,51,67,82,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,343,359,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,83,100,115,132,147,164,180,196,212,230,246,262,278,294,310,327,342,358,373,390,405],
[36,51,67,82,101,116,132,147,165,180,197,212,230,246,263,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405],
[37,52,68,82,100,115,132,147,164,180,196,212,230,246,262,278,294,310,327,342,358,373,390,405],
[36,51,67,82,101,116,132,147,165,180,197,212,230,246,262,278,295,310,327,342,358,373,390,405],
[37,51,67,82,101,116,132,147,165,180,197,213,230,246,263,278,295,310,328,343,359,374,390,405],
[37,52,67,82,101,116,132,148,165,181,197,213,231,246,263,279,295,311,328,343,359,374,391,405]
]

// ---- Chinese lunar calendar (农历), solar years 1900-2098.
//      Table packed the classic way: bit 16 = leap month is 30 days,
//      bits 15..4 = months 1..12 big/small, bits 3..0 = leap month number.
//      Generated from the lunardate library and verified against it on
//      1000 random dates across the range — see memory log 2026-09-05.
var lunarInfo = [
0x4bd8,0x4ae0,0xa570,0x54d5,0xd260,0xd950,0x16554,0x56a0,0x9ad0,0x55d2,0x4ae0,0xa5b6,0xa4d0,0xd250,0x1d255,0xb540,
0xd6a0,0xada2,0x95b0,0x14977,0x4970,0xa4b0,0xb4b5,0x6a50,0x6d40,0x1ab54,0x2b60,0x9570,0x52f2,0x4970,0x6566,0xd4a0,
0xea50,0x6e95,0x5ad0,0x2b60,0x186e3,0x92e0,0x1c8d7,0xc950,0xd4a0,0x1d8a6,0xb550,0x56a0,0x1a5b4,0x25d0,0x92d0,0xd2b2,
0xa950,0xb557,0x6ca0,0xb550,0x15355,0x4da0,0xa5d0,0x14573,0x52b0,0xa9a8,0xe950,0x6aa0,0xaea6,0xab50,0x4b60,0xaae4,
0xa570,0x5260,0xf263,0xd950,0x5b57,0x56a0,0x96d0,0x4dd5,0x4ad0,0xa4d0,0xd4d4,0xd250,0xd558,0xb540,0xb5a0,0x195a6,
0x95b0,0x49b0,0xa974,0xa4b0,0xb27a,0x6a50,0x6d40,0xaf46,0xab60,0x9570,0x4af5,0x4970,0x64b0,0x74a3,0xea50,0x6b58,
0x5ac0,0xab60,0x96d5,0x92e0,0xc960,0xd954,0xd4a0,0xda50,0x7552,0x56a0,0xabb7,0x25d0,0x92d0,0xcab5,0xa950,0xb4a0,
0xbaa4,0xad50,0x55d9,0x4ba0,0xa5b0,0x15176,0x52b0,0xa930,0x7954,0x6aa0,0xad50,0x5b52,0x4b60,0xa6e6,0xa4e0,0xd260,
0xea65,0xd530,0x5aa0,0x76a3,0x96d0,0x4afb,0x4ad0,0xa4d0,0x1d0b6,0xd250,0xd520,0xdd45,0xb5a0,0x56d0,0x55b2,0x49b0,
0xa577,0xa4b0,0xaa50,0x1b255,0x6d20,0xada0,0x14b63,0x9370,0x49f8,0x4970,0x64b0,0x168a6,0xea50,0x6aa0,0x1a6c4,0xaae0,
0x92e0,0xd2e3,0xc960,0xd557,0xd4a0,0xda50,0x5d55,0x56a0,0xa6d0,0x55d4,0x52d0,0xa9b8,0xa950,0xb4a0,0xb6a6,0xad50,
0x55a0,0xaba4,0xa5b0,0x52b0,0xb273,0x6930,0x7337,0x6aa0,0xad50,0x14b55,0x4b60,0xa570,0x54e4,0xd160,0xe968,0xd520,
0xdaa0,0x16aa6,0x56d0,0x4ae0,0xa9d4,0xa2d0,0xd150,0xf252
]

var lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
var lunarDays = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
  "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
  "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
var ganzhiStems = "甲乙丙丁戊己庚辛壬癸"
var ganzhiBranches = "子丑寅卯辰巳午未申酉戌亥"

function lunarMonthBig(year, month) {
  return (lunarInfo[year - 1900] & (0x10000 >> month)) !== 0
}

function lunarLeapMonth(year) {
  return lunarInfo[year - 1900] & 0xf
}

function lunarLeapDays(year) {
  if (!lunarLeapMonth(year)) return 0
  return (lunarInfo[year - 1900] & 0x10000) ? 30 : 29
}

function lunarYearDays(year) {
  var sum = 348
  for (var i = 0x8000; i > 0x8; i >>= 1) sum += (lunarInfo[year - 1900] & i) ? 1 : 0
  return sum + lunarLeapDays(year)
}

// Returns { year, month, isLeap, day } in lunar terms, or null outside
// the table's 1900-01-31 .. 2099 range.
function solarToLunar(year, month, day) {
  if (year < 1900 || year > 2099) return null
  var offset = Math.round((Date.UTC(year, month, day) - Date.UTC(1900, 0, 31)) / MS_PER_DAY)
  if (offset < 0) return null
  var y = 1900
  while (offset >= lunarYearDays(y)) {
    offset -= lunarYearDays(y)
    y++
  }
  var lm = lunarLeapMonth(y)
  var mm = 1
  var isLeap = false
  while (true) {
    var length = lunarMonthBig(y, mm) ? 30 : 29
    if (lm === mm && !isLeap) {
      if (offset < length) break
      offset -= length
      if (offset < lunarLeapDays(y)) {
        isLeap = true
        break
      }
      offset -= lunarLeapDays(y)
      mm++
      continue
    }
    if (offset < length) break
    offset -= length
    mm++
  }
  return { year: y, month: mm, isLeap: isLeap, day: offset + 1 }
}

function lunarYearName(lunarYear) {
  return ganzhiStems.charAt((lunarYear - 4) % 10) + ganzhiBranches.charAt((lunarYear - 4) % 12)
}

// Solar term (节气) falling on this solar date, or null. 2-char name.
function solarTerm(year, month, day) {
  var row = termInfo[year - 1900]
  if (!row) return null
  // QML passes 0-based months; the table stores 1-based ones.
  var packed = ((month + 1) << 5) | day
  var names = ["小寒","大寒","立春","雨水","惊蛰","春分","清明","谷雨","立夏","小满","芒种",
               "夏至","小暑","大暑","立秋","处暑","白露","秋分","寒露","霜降","立冬","小雪","大雪","冬至"]
  for (var i = 0; i < 24; i++) {
    if (row[i] === packed) return names[i]
  }
  return null
}

var solarFestivals = { "1,1": "元旦", "5,1": "劳动节", "10,1": "国庆节" }
var lunarFestivals = { "1,1": "春节", "1,15": "元宵", "5,5": "端午", "7,7": "七夕",
                       "8,15": "中秋", "9,9": "重阳", "12,8": "腊八" }

// Chinese festival (节日) on this solar date, or null. Checked before the
// solar term so 清明 (a term that is also a holiday) renders as 清明 either
// way, and lunar festivals override whatever lunar day label would show.
function festivalLabel(year, month, day) {
  var fixed = solarFestivals[(month + 1) + "," + day]
  if (fixed) return fixed
  var lunar = solarToLunar(year, month, day)
  if (!lunar || lunar.isLeap) return null
  var named = lunarFestivals[lunar.month + "," + lunar.day]
  if (named) return named
  // 除夕: last day of the lunar year. With a leap 12th month the year
  // actually ends in the leap month, so regular 腊月's last day is not it.
  if (lunar.month === 12 && lunarLeapMonth(lunar.year) !== 12) {
    var len = lunarMonthBig(lunar.year, 12) ? 30 : 29
    if (lunar.day === len) return "除夕"
  }
  return null
}

// Compact label for a calendar cell: festival first, then solar term, then
// the lunar month name on day one (so every month announces itself in
// place), otherwise the day name.
function lunarDayLabel(year, month, day) {
  var fest = festivalLabel(year, month, day)
  if (fest) return fest
  var term = solarTerm(year, month, day)
  if (term) return term
  var lunar = solarToLunar(year, month, day)
  if (!lunar) return ""
  if (lunar.day === 1)
    return (lunar.isLeap ? "闰" : "") + lunarMonths[lunar.month - 1]
  return lunarDays[lunar.day - 1]
}

// Full label for the hero row: "丙午年七月廿四".
function lunarFullLabel(year, month, day) {
  var lunar = solarToLunar(year, month, day)
  if (!lunar) return ""
  return lunarYearName(lunar.year) + "年"
    + (lunar.isLeap ? "闰" : "") + lunarMonths[lunar.month - 1]
    + lunarDays[lunar.day - 1]
}

var zhLongMonths = ["一月", "二月", "三月", "四月", "五月", "六月",
                    "七月", "八月", "九月", "十月", "十一月", "十二月"]

// This Qt build rejects QLocale args passed to Qt.formatDate/DateTime from
// QML JS, so month names are localized manually: swap MMMM for the Chinese
// name, then call the plain 2-arg formatter.
function localizeMonthNames(format, month) {
  return format.replace(/MMMM/g, zhLongMonths[month])
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockNeedsSeconds: clockNeedsSeconds,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    localizeMonthNames: localizeMonthNames,
    solarToLunar: solarToLunar,
    solarTerm: solarTerm,
    festivalLabel: festivalLabel,
    lunarDayLabel: lunarDayLabel,
    lunarFullLabel: lunarFullLabel
  }
}
