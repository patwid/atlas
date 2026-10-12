import { clickedOutside } from "./interaction.ffi.mjs"

export function showModal(id) {
  const dialog = document.getElementById(id)
  if (!dialog) return
  if (!dialog.dataset.lightDismissBound) {
    dialog.addEventListener("click", (event) => {
      if (clickedOutside(dialog, event)) dialog.close()
    })
    dialog.dataset.lightDismissBound = "true"
  }
  dialog.showModal()
}
