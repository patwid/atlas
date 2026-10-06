/// <reference path="../pb_data/types.d.ts" />
// athlete_settings: one row per athlete for their own settings, so far the heart-rate zones (the maximum heart
// rate and where each of the five zones starts, in bpm). The row's ID is the athlete's user ID, so two devices
// that save offline write to the same row instead of making two. See docs/adr/0034-heart-rate-zone-settings.md.
const ME = "@request.auth.id"

const coachOf = (athleteExpr) =>
  `(@collection.coach_grants.athlete ?= ${athleteExpr} && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)`

const bpm = (name) => ({ type: "number", name, required: true, min: 30, max: 250, onlyInt: true })

migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users")
    app.save(new Collection({
      type: "base",
      name: "athlete_settings",
      listRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      viewRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      createRule: `@request.body.owner = ${ME} && @request.body.id = ${ME}`,
      updateRule: `owner = ${ME} && @request.body.owner:changed = false`,
      deleteRule: null,
      fields: [
        { type: "bool", name: "deleted" },
        { type: "autodate", name: "created", onCreate: true },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        { type: "relation", name: "owner", collectionId: users.id, maxSelect: 1, required: true, cascadeDelete: true },
        bpm("max_hr"),
        bpm("hr_zone1_min"),
        bpm("hr_zone2_min"),
        bpm("hr_zone3_min"),
        bpm("hr_zone4_min"),
        bpm("hr_zone5_min"),
      ],
      // Not unique on owner: the create rule already ties the ID to the owner, and a second create must fail on the
      // ID (which the client turns into an update), not on the owner.
      indexes: [
        "CREATE INDEX `idx_athlete_settings_owner` ON `athlete_settings` (owner)",
        "CREATE INDEX `idx_athlete_settings_updated` ON `athlete_settings` (updated)",
      ],
    }))
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("athlete_settings"))
  },
)
