// Hard-deletes soft-deleted rows once every device has had time to sync the deletion.
// See docs/adr/0014-purge-soft-deleted-rows.md.

// Children before parents, so nothing is removed by a cascade before its own turn.
const COLLECTIONS = ["matches", "activities", "assignments", "workouts", "plan_shares", "plans", "coach_grants"]
const BATCH = 500

function retentionDays() {
  const raw = parseFloat($os.getenv("ATLAS_PURGE_RETENTION_DAYS"))
  return isNaN(raw) || raw < 0 ? 90 : raw
}

function purge(days) {
  days = days === undefined ? retentionDays() : days
  const cutoff = new Date(Date.now() - days * 86400 * 1000).toISOString().replace("T", " ")
  const removed = {}
  for (const name of COLLECTIONS) {
    removed[name] = 0
    for (;;) {
      const rows = $app.findRecordsByFilter(name, "deleted = true && updated < {:cutoff}", "updated", BATCH, 0, { cutoff: cutoff })
      for (const row of rows) {
        try {
          $app.delete(row)
          removed[name]++
        } catch (err) {
          // It may already be gone through a cascade from its parent; anything else is a real error.
          let stillThere = true
          try { $app.findRecordById(name, row.id) } catch (_) { stillThere = false }
          if (stillThere) throw err
        }
      }
      if (rows.length < BATCH) break
    }
  }
  return removed
}

module.exports = { purge, retentionDays }
