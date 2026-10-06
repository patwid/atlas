// Strava's brand rules say the logos must never be modified, altered or animated (ADR 0027). The two files in
// frontend/assets/strava come from Strava's download packages; these checksums are those of the originals, so
// an edit, a "cleaning" by an optimiser or a replacement by something else fails here.
import { test } from "node:test"
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFileSync, readdirSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const dir = join(dirname(fileURLToPath(import.meta.url)), "../assets/strava")
const original = {
  "btn_strava_connect_with_orange.svg": "cc5b78798ae02919cfde7c2d9f66a9298e51d2c0bb3e9523c9d9b1aec8a63857",
  "api_logo_pwrdBy_strava_horiz_orange.svg": "888fdbc996942fe2420bf10c8d47612585e522fd3ebed0043c43487f87d43287",
}
const sha256 = (name) => createHash("sha256").update(readFileSync(join(dir, name))).digest("hex")

test("Strava's brand files are exactly the ones Strava provides", () => {
  for (const [name, checksum] of Object.entries(original)) assert.equal(sha256(name), checksum, name)
})

test("nothing else is kept in the Strava assets folder", () => {
  assert.deepEqual(readdirSync(dir).sort(), Object.keys(original).sort())
})

test("the files hold only plain shapes: no scripts, links or embedded images", () => {
  for (const name of Object.keys(original)) {
    const text = readFileSync(join(dir, name), "utf8")
    assert.doesNotMatch(text, /<script|onload|onclick|onerror|foreignObject|href=|javascript:|<image|<style/i, name)
  }
})
