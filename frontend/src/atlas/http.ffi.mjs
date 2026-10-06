// One fetch, reported as (status, body). Status 0 means no answer: offline, DNS, timeout or abort.
export function send(method, url, token, body, callback) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 20000)
  const headers = {}
  if (token !== "") headers["Authorization"] = token
  if (body !== "") headers["Content-Type"] = "application/json"
  fetch(url, { method, headers, body: body === "" ? undefined : body, signal: controller.signal })
    .then(async (response) => callback(response.status, await response.text()))
    .catch(() => callback(0, ""))
    .finally(() => clearTimeout(timer))
}
