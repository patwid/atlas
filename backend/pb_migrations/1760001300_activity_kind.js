/// <reference path="../pb_data/types.d.ts" />
// An activity's kind, zone, parts and notes, as a workout has them. None is required, so rows saved before, Strava's
// and app versions that do not know them keep working. See docs/adr/0121-activity-kind-and-fields-of-a-workout.md.
migrate(
  (app) => {
    const activities = app.findCollectionByNameOrId("activities")
    activities.fields.add(new SelectField({ name: "kind", maxSelect: 1, values: ["run", "interval", "race"] }))
    activities.fields.add(new NumberField({ name: "zone", min: 0, max: 5, onlyInt: true }))
    activities.fields.add(new JSONField({ name: "steps", maxSize: 100000 }))
    activities.fields.add(new TextField({ name: "description", max: 5000 }))
    app.save(activities)
  },
  (app) => {
    const activities = app.findCollectionByNameOrId("activities")
    for (const name of ["kind", "zone", "steps", "description"]) activities.fields.removeByName(name)
    app.save(activities)
  },
)
