// A uniformly random integer in 0..n-1 from the browser's secure random source.
export function randomInt(n) {
  const limit = Math.floor(0x100000000 / n) * n
  const buffer = new Uint32Array(1)
  do {
    crypto.getRandomValues(buffer)
  } while (buffer[0] >= limit)
  return buffer[0] % n
}
