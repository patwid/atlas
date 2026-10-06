// localStorage can throw (private windows, blocked site data) or be missing, so every call is guarded.
export function get(key) {
  try { return localStorage.getItem(key) ?? "" } catch { return "" }
}
export function set(key, value) {
  try { localStorage.setItem(key, value) } catch {}
}
export function remove(key) {
  try { localStorage.removeItem(key) } catch {}
}
