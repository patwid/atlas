export function nowSeconds() {
  return Math.floor(Date.now() / 1000)
}

// Minutes east of UTC right now (for example 120 in Swiss summer time).
export function utcOffsetMinutes() {
  return -new Date().getTimezoneOffset()
}
