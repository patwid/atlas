// Shared test harness: starts a throwaway PocketBase with the committed migrations and hooks.
import assert from "node:assert/strict"
import { spawn, execFileSync } from "node:child_process"
import { mkdtempSync, cpSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"

const backend = join(dirname(fileURLToPath(import.meta.url)), "..")

export const randomPort = () => 18000 + Math.floor(Math.random() * 20000)

let n = 0
export const id = () => (`t${Date.now().toString(36)}${(n++).toString(36)}${Math.random().toString(36).slice(2)}`).replace(/[^a-z0-9]/g, "").padEnd(15, "0").slice(0, 15)

/** `publicDir`: a built frontend to serve from pb_public (optional). */
export async function startPocketBase(env = {}, { publicDir } = {}) {
  const port = randomPort()
  const url = `http://127.0.0.1:${port}`
  const dir = mkdtempSync(join(tmpdir(), "atlas-pb-"))
  cpSync(join(backend, "pb_migrations"), join(dir, "pb_migrations"), { recursive: true })
  cpSync(join(backend, "pb_hooks"), join(dir, "pb_hooks"), { recursive: true })
  if (publicDir) cpSync(publicDir, join(dir, "pb_public"), { recursive: true })
  const pb = (...args) => ["--dir", join(dir, "pb_data"), "--migrationsDir", join(dir, "pb_migrations"), "--hooksDir", join(dir, "pb_hooks"), ...args]
  const childEnv = { ...process.env, ATLAS_PUBLIC_URL: url, NO_PROXY: "127.0.0.1,localhost", no_proxy: "127.0.0.1,localhost", ...env }
  execFileSync("pocketbase", ["superuser", "upsert", "admin@example.com", "adminpass123", ...pb()], { stdio: "pipe", env: childEnv })
  const server = spawn("pocketbase", ["serve", `--http=127.0.0.1:${port}`, ...pb()], { stdio: "pipe", env: childEnv })
  let log = ""
  server.stdout.on("data", (d) => (log += d))
  server.stderr.on("data", (d) => (log += d))
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(`${url}/api/health`)).ok) break } catch {}
    await new Promise((r) => setTimeout(r, 100))
  }

  const api = async (method, path, { token, body, raw } = {}) => {
    const res = await fetch(`${url}/api/${path}`, {
      method,
      redirect: "manual",
      headers: { "content-type": "application/json", ...(token ? { authorization: token } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    })
    const text = await res.text()
    let parsed = null
    try { parsed = text ? JSON.parse(text) : null } catch { parsed = text }
    return { status: res.status, body: parsed, headers: res.headers }
  }
  const auth = await api("POST", "collections/_superusers/auth-with-password", { body: { identity: "admin@example.com", password: "adminpass123" } })
  const admin = auth.body.token

  const people = {}
  const as = (name) => people[name].token
  const tokenOf = (who) => (who && (people[who] ? as(who) : who === "admin" ? admin : undefined)) || undefined
  const h = {
    url, admin, people, api, as,
    create: (who, collection, body) => api("POST", `collections/${collection}/records`, { token: tokenOf(who), body }),
    update: (who, collection, rid, body) => api("PATCH", `collections/${collection}/records/${rid}`, { token: tokenOf(who), body }),
    get: (who, collection, rid) => api("GET", `collections/${collection}/records/${rid}`, { token: tokenOf(who) }),
    list: (who, collection, filter = "") =>
      api("GET", `collections/${collection}/records?perPage=200${filter ? `&filter=${encodeURIComponent(filter)}` : ""}`, { token: tokenOf(who) }),
    // Every test gets its own four users, so grants and shares never leak between tests.
    world: async () => {
      h.run = (h.run || 0) + 1
      for (const name of ["alice", "bob", "carol", "dave"]) {
        const email = `${name}${h.run}@example.com`
        const r = await api("POST", "collections/users/records", {
          token: admin,
          body: { email, password: "password123", passwordConfirm: "password123", name },
        })
        assert.equal(r.status, 200, JSON.stringify(r.body))
        const login = await api("POST", "collections/users/auth-with-password", { body: { identity: email, password: "password123" } })
        people[name] = { id: r.body.id, token: login.body.token, email }
      }
    },
    log: () => log,
    stop: () => { server.kill(); rmSync(dir, { recursive: true, force: true }) },
  }
  return h
}
