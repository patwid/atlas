// Daily purge of soft-deleted rows. See docs/adr/0014-purge-soft-deleted-rows.md.
// Retention comes from ATLAS_PURGE_RETENTION_DAYS (default 90). Superusers can run it on demand:
// POST /api/crons/atlas_purge_deleted
cronAdd("atlas_purge_deleted", "17 3 * * *", () => {
  const purge = require(`${__hooks}/lib/purge.js`)
  const removed = purge.purge()
  $app.logger().info("purged soft-deleted rows", "removed", JSON.stringify(removed))
})
