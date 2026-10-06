/// <reference path="../pb_data/types.d.ts" />
// Display names on coach grants, so a device can show who a coach or athlete is without the users
// collection (which is not synced and not readable beyond linked users). They are labels only: the
// athlete writes them when granting access. See docs/adr/0023-assignments-and-coaches.md.
migrate(
  (app) => {
    const grants = app.findCollectionByNameOrId("coach_grants")
    grants.fields.add(new TextField({ name: "athlete_name", max: 200 }))
    grants.fields.add(new TextField({ name: "coach_name", max: 200 }))
    app.save(grants)
  },
  (app) => {
    const grants = app.findCollectionByNameOrId("coach_grants")
    grants.fields.removeByName("athlete_name")
    grants.fields.removeByName("coach_name")
    app.save(grants)
  },
)
