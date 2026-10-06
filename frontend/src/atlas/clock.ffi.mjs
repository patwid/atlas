export function nowSeconds() {
  return Math.floor(Date.now() / 1000)
}

// Minutes east of UTC right now (for example 120 in Swiss summer time).
export function utcOffsetMinutes() {
  return -new Date().getTimezoneOffset()
}

// Minutes east of UTC that apply on a given local date and time (daylight saving included).
export function utcOffsetAtLocal(year, month, day, hour, minute) {
  return -new Date(year, month - 1, day, hour, minute).getTimezoneOffset()
}

// Minutes east of UTC that applied at a UTC timestamp such as `2026-10-01 05:30:00.000Z`.
export function utcOffsetAtUtc(timestamp) {
  return -new Date(timestamp.replace(" ", "T")).getTimezoneOffset()
}
