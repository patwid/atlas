export function showModal(id) {
  const dialog = document.getElementById(id)
  if (!dialog) return
  if (!dialog.dataset.lightDismissBound) {
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close()
    })
    dialog.dataset.lightDismissBound = "true"
  }
  dialog.showModal()
}
