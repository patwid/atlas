/// <reference path="../pb_data/types.d.ts" />
// goals: an athlete's race goals, any number of them, each a distance and a time to run it in. One row per goal,
// owned by the athlete and readable by their coach, like athlete_settings. See docs/adr/0115-race-goals.md.
const ME = "@request.auth.id"

const coachOf = (athleteExpr) =>
  `(@collection.coach_grants.athlete ?= ${athleteExpr} && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)`

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users")
    app.save(new Collection({
      type: "base",
      name: "goals",
      listRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      viewRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      createRule: `@request.body.owner = ${ME}`,
      updateRule: `owner = ${ME} && @request.body.owner:changed = false`,
      deleteRule: null,
      fields: [
        { type: "bool", name: "deleted" },
        { type: "autodate", name: "created", onCreate: true },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        { type: "relation", name: "owner", collectionId: users.id, maxSelect: 1, required: true, cascadeDelete: true },
        // Up to 1000 km in up to 48 hours, the limits of the app's distance and time fields.
        { type: "number", name: "distance_m", required: true, min: 1, max: 1000000 },
        { type: "number", name: "time_s", required: true, min: 1, max: 172800, onlyInt: true },
      ],
      indexes: [
        "CREATE INDEX `idx_goals_owner_updated` ON `goals` (owner, updated)",
      ],
    }))
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("goals"))
  },
)
