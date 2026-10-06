// Look up a user by exact e-mail address so they can be selected for a coach grant or an assignment.
// See docs/adr/0010-user-lookup-by-email.md.
// At most 30 lookups per user per 10 minutes, to make probing for e-mail addresses slow.
routerAdd("GET", "/api/atlas/users/lookup", (e) => {
  const key = "lookup:" + e.auth.id
  const now = Date.now()
  const used = ($app.store().get(key) || []).filter((t) => now - t < 10 * 60 * 1000)
  if (used.length >= 30) {
    throw new TooManyRequestsError("Too many lookups, try again later.")
  }
  used.push(now)
  $app.store().set(key, used)

  const email = String(e.request.url.query().get("email") || "").trim().toLowerCase()
  if (!email || email.length > 254 || email.indexOf("@") < 1) {
    throw new BadRequestError("An e-mail address is required.")
  }
  let user
  try {
    user = $app.findAuthRecordByEmail("users", email)
  } catch (_) {
    throw new NotFoundError("No user with this e-mail address.")
  }
  if (user.id === e.auth.id) {
    throw new BadRequestError("That is you.")
  }
  return e.json(200, { id: user.id, name: user.getString("name") })
}, $apis.requireAuth("users"))
