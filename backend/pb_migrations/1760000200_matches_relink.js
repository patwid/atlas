/// <reference path="../pb_data/types.d.ts" />
// A match can be moved to another workout of another assignment of the same user ("re-link"). A removed
// match keeps its row (soft delete) and the row's activity is unique, so linking the activity again has
// to change the existing row instead of creating a new one. See docs/adr/0026-today-screen.md.
const ME = "@request.auth.id"

migrate(
  (app) => {
    const matches = app.findCollectionByNameOrId("matches")
    matches.updateRule =
      `owner = ${ME} && @request.body.owner:changed = false && @request.body.activity:changed = false` +
      ` && (@request.body.assignment:changed = false || @request.body.assignment.athlete = ${ME})`
    app.save(matches)
  },
  (app) => {
    const matches = app.findCollectionByNameOrId("matches")
    matches.updateRule =
      `owner = ${ME} && @request.body.owner:changed = false && @request.body.activity:changed = false` +
      ` && @request.body.assignment:changed = false`
    app.save(matches)
  },
)
