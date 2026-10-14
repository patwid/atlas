// app.css is hand-written (ADR 0044): a syntax error there would only show as a broken page, so it is parsed here.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import * as csstree from "css-tree"

const assets = join(dirname(fileURLToPath(import.meta.url)), "../assets")
const css = readFileSync(join(assets, "app.css"), "utf8")
// Fluent's design tokens (ADR 0133), which app.css uses, are defined in the stylesheet loaded before it.
const theme = readFileSync(join(assets, "fluent-theme.css"), "utf8")

test("app.css parses without errors", () => {
  const errors = []
  csstree.parse(css, { positions: true, onParseError: (error) => errors.push(error.formattedMessage ?? error.message) })
  assert.deepEqual(errors, [])
})

test("every custom property app.css uses is defined in it", () => {
  const defined = new Set([...(css + theme).matchAll(/(--[\w-]+)\s*:/g)].map((m) => m[1]))
  // Set from code at run time: the slider's fill and a time picker angle.
  for (const name of ["--fill", "--angle"]) defined.add(name)
  const used = new Set([...css.matchAll(/var\((--[\w-]+)/g)].map((m) => m[1]))
  assert.deepEqual([...used].filter((name) => !defined.has(name)), [])
})
