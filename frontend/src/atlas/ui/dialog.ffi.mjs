import { clickedOutside, showFluent } from "./interaction.ffi.mjs"

export function showModal(id) {
  const dialog = document.getElementById(id)
  if (!dialog) return
  // A Fluent UI dialog (ADR 0133): its own show(), and its action form closes it.
  if (dialog.localName === "fluent-dialog") return showFluent(dialog)
  if (!dialog.dataset.lightDismissBound) {
    dialog.addEventListener("click", (event) => {
      if (clickedOutside(dialog, event)) dialog.close()
    })
    dialog.dataset.lightDismissBound = "true"
  }
  dialog.showModal()
}
