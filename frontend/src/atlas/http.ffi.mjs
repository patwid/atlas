// One fetch, reported as (status, body). Status 0 means no answer: offline, DNS, timeout or abort.
// Only a failed request counts as "no answer": an error thrown by the callback is the app's own
// bug and must not be reported to it as a network failure.
export function send(method, url, token, body, callback) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 20000)
  const headers = {}
  if (token !== "") headers["Authorization"] = token
  if (body !== "") headers["Content-Type"] = "application/json"
  fetch(url, { method, headers, body: body === "" ? undefined : body, signal: controller.signal })
    .then(async (response) => ({ status: response.status, text: await response.text() }))
    .then(
      (answer) => answer,
      () => ({ status: 0, text: "" }),
    )
    .then((answer) => {
      clearTimeout(timer)
      callback(answer.status, answer.text)
    })
}
