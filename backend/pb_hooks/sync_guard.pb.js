// Optimistic-concurrency guard for synced collections. See docs/adr/0011-sync-conflict-guard.md.
// A client update must carry `base_updated`, the `updated` value of the record it edited. If the
// server's record has changed since then, the update is refused with 409 (a field error on
// `base_updated`), the client fetches the current record and keeps its version as a "conflicted copy".
onRecordUpdateRequest((e) => {
  if (e.hasSuperuserAuth()) {
    return e.next()
  }
  const body = e.requestInfo().body || {}
  const base = body.base_updated
  if (typeof base !== "string" || base === "") {
    throw new BadRequestError("base_updated is required when updating this collection.")
  }
  const original = e.record.original()
  if (base !== original.getString("updated")) {
    // A replayed update that already took effect (the response was lost) is not a conflict.
    let identical = true
    for (const field of e.record.collection().fields) {
      const name = field.name
      if (name === "updated" || name === "created") continue
      if (JSON.stringify(e.record.get(name)) !== JSON.stringify(original.get(name))) {
        identical = false
        break
      }
    }
    if (!identical) {
      throw new ApiError(409, "The record was changed since base_updated.", {
        base_updated: { code: "conflict", message: "The record was changed since base_updated." },
      })
    }
  }
  return e.next()
}, "coach_grants", "plans", "plan_shares", "workouts", "assignments", "activities", "matches")
