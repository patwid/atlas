// Fluent UI's web components (ADR 0133, spike). Importing the bundle defines the fluent-* custom elements. It needs a
// browser, so it is only imported where there are custom elements: the unit tests import this module in Node.
export function define() {
  if (globalThis.customElements) import("./fluent/web-components.min.mjs")
}
