// Fluent UI's web components (ADR 0133). Importing the bundle defines the fluent-* custom elements. It needs a
// browser, so it is only imported where there are custom elements: the unit tests import this module in Node.
export function define() {
  if (!globalThis.customElements) return
  import("./fluent/web-components.min.mjs")
  forwardToControls()
}

// Fluent's text input and textarea keep their <input> and <textarea> in their shadow root and pass on neither the
// field's help or error (aria-describedby), nor that it is wrong (aria-invalid), nor the keyboard a phone should show
// (inputmode). This copies them from the element onto its control whenever the page changes. An id from the page
// cannot be named from inside a shadow root, so the description is given as elements, which can.
const controls = "fluent-text-input, fluent-textarea"
const copied = ["aria-invalid", "inputmode"]

function forwardToControls() {
  const forward = () => {
    for (const host of document.querySelectorAll(controls)) {
      const control = host.shadowRoot?.querySelector("input, textarea")
      if (!control) continue
      const ids = host.getAttribute("aria-describedby")
      control.ariaDescribedByElements = ids
        ? ids.split(/\s+/).map((id) => document.getElementById(id)).filter(Boolean)
        : null
      for (const name of copied) {
        const value = host.getAttribute(name)
        if (value === null) control.removeAttribute(name)
        else control.setAttribute(name, value)
      }
    }
  }
  // The page's own nodes only: a change inside a shadow root, such as one made here, does not come back.
  new MutationObserver(forward).observe(document.documentElement, {
    subtree: true, childList: true, attributes: true, attributeFilter: ["aria-describedby", ...copied],
  })
  for (const name of ["fluent-text-input", "fluent-textarea"]) customElements.whenDefined(name).then(forward)
}
