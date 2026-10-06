// A minimal fake of the Strava API for hook tests. Records every call in `calls`.
import { createServer } from "node:http"

export async function startFakeStrava({ webhookUrl } = {}) {
  const state = { calls: [], activities: new Map(), laps: new Map(), athleteId: 1001, tokenSeq: 0, rejectCode: false }
  const server = createServer(async (req, res) => {
    const url = new URL(req.url, "http://x")
    let raw = ""
    for await (const chunk of req) raw += chunk
    const form = Object.fromEntries(new URLSearchParams(raw))
    state.calls.push({ method: req.method, path: url.pathname, query: Object.fromEntries(url.searchParams), form, auth: req.headers.authorization })
    const json = (code, body) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(body)) }
    const expiresIn = state.expiresIn ?? 21600
    if (url.pathname === "/oauth/token" && req.method === "POST") {
      if (form.grant_type === "authorization_code") {
        if (state.rejectCode || form.code !== "good-code") return json(400, { message: "Bad Request" })
        return json(200, {
          access_token: `access-${++state.tokenSeq}`, refresh_token: `refresh-${state.tokenSeq}`,
          expires_at: Math.floor(Date.now() / 1000) + expiresIn, athlete: { id: state.athleteId },
        })
      }
      if (form.grant_type === "refresh_token") {
        return json(200, { access_token: `access-${++state.tokenSeq}`, refresh_token: `refresh-${state.tokenSeq}`, expires_at: Math.floor(Date.now() / 1000) + 21600 })
      }
    }
    if (url.pathname === "/oauth/deauthorize") return json(200, { access_token: "x" })
    if (url.pathname === "/api/v3/athlete/activities") return json(200, [...state.activities.values()])
    const lapsMatch = url.pathname.match(/^\/api\/v3\/activities\/(\d+)\/laps$/)
    if (lapsMatch) return json(200, state.laps.get(lapsMatch[1]) ?? [])
    const actMatch = url.pathname.match(/^\/api\/v3\/activities\/(\d+)$/)
    if (actMatch) return state.activities.has(Number(actMatch[1])) ? json(200, state.activities.get(Number(actMatch[1]))) : json(404, { message: "Not Found" })
    if (url.pathname === "/api/v3/push_subscriptions" && req.method === "POST") {
      if (webhookUrl) {
        const check = await fetch(`${form.callback_url}?hub.mode=subscribe&hub.verify_token=${form.verify_token}&hub.challenge=abc123`)
        const body = await check.json()
        if (body["hub.challenge"] !== "abc123") return json(400, { message: "validation failed" })
      }
      return json(201, { id: 777 })
    }
    json(404, { message: "not found" })
  })
  await new Promise((r) => server.listen(0, "127.0.0.1", r))
  const base = `http://127.0.0.1:${server.address().port}`
  const activity = (id, extra = {}) => ({
    id, name: `Run ${id}`, sport_type: "Run", type: "Run", start_date: "2026-10-01T07:00:00Z",
    distance: 10234.5, moving_time: 3000, elapsed_time: 3100, total_elevation_gain: 55.5, average_heartrate: 150.4, max_heartrate: 178, ...extra,
  })
  return { base, state, activity, stop: () => server.close() }
}
