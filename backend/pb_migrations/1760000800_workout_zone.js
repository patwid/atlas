/// <reference path="../pb_data/types.d.ts" />
// The target training zone of a workout, 1 to 5, 0 for none. Not required, so rows saved before and app versions
// that do not know it keep working. See docs/adr/0105-workout-target-zone.md.
migrate(
  (app) => {
    const workouts = app.findCollectionByNameOrId("workouts")
    workouts.fields.add(new NumberField({ name: "zone", min: 0, max: 5, onlyInt: true }))
    app.save(workouts)
  },
  (app) => {
    const workouts = app.findCollectionByNameOrId("workouts")
    workouts.fields.removeByName("zone")
    app.save(workouts)
  },
)
