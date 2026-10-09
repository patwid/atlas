// A file the user picks, read in the browser (ADR 0100). Nothing is uploaded: the bytes go to Gleam.
import { BitArray } from "../gleam.mjs"

// Opens the picker of a (hidden) file input.
export function pick(id) {
  if (typeof document === "undefined") return
  document.getElementById(id)?.click()
}

// Reads the file chosen in a file input and reports callback(ok, name, bytes). Nothing is reported when no file
// was chosen. The input is cleared, so picking the same file again is noticed.
export function read(id, callback) {
  const input = typeof document === "undefined" ? null : document.getElementById(id)
  const file = input?.files?.[0]
  if (!file) return
  input.value = ""
  file.arrayBuffer().then(
    (buffer) => callback(true, file.name, new BitArray(new Uint8Array(buffer))),
    (error) => {
      console.warn("file:", error)
      callback(false, file.name, new BitArray(new Uint8Array(0)))
    },
  )
}
