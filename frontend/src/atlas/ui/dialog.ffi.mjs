import { clickedOutside } from "./interaction.ffi.mjs"

export function showModal(id) {
  const dialog = document.getElementById(id)
  if (!dialog) return
  // A Fluent UI dialog (ADR 0133, spike): its own show(), and its action form closes it, which a form with
  // method="dialog" cannot do from outside the dialog's shadow root.
  if (dialog.localName === "fluent-dialog") {
    if (!dialog.dataset.submitBound) {
      dialog.addEventListener("submit", (event) => {
        if (event.target.getAttribute("method") !== "dialog") return
        event.preventDefault()
        dialog.hide()
      })
      dialog.dataset.submitBound = "true"
    }
    dialog.show()
    return
  }
  if (!dialog.dataset.lightDismissBound) {
    dialog.addEventListener("click", (event) => {
      if (clickedOutside(dialog, event)) dialog.close()
    })
    dialog.dataset.lightDismissBound = "true"
  }
  dialog.showModal()
}
