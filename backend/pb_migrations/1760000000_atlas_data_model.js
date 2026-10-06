/// <reference path="../pb_data/types.d.ts" />
// Atlas data model and API rules. See docs/adr/0009-data-model-and-api-rules.md.

const ME = "@request.auth.id"

// True when the signed-in user is a coach of the athlete given by `athleteExpr`.
const coachOf = (athleteExpr) =>
  `(@collection.coach_grants.athlete ?= ${athleteExpr} && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)`

// True when the signed-in user may read the plan given by `planExpr`.
const planReadable = (planExpr, ownerExpr, visibilityExpr) =>
  `(${ownerExpr} = ${ME} || (${visibilityExpr} = "public" && ${ME} != "")` +
  ` || (@collection.plan_shares.plan ?= ${planExpr} && @collection.plan_shares.user ?= ${ME} && @collection.plan_shares.deleted ?= false)` +
  ` || (@collection.assignments.plan ?= ${planExpr} && @collection.assignments.athlete ?= ${ME} && @collection.assignments.deleted ?= false))`

const unchanged = (...fields) => fields.map((f) => `@request.body.${f}:changed = false`).join(" && ")

const sync = (extra = []) => [
  { type: "bool", name: "deleted" },
  { type: "autodate", name: "created", onCreate: true },
  { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
  ...extra,
]

const idx = (table, cols, unique = false, where = "") =>
  `CREATE ${unique ? "UNIQUE " : ""}INDEX \`idx_${table}_${cols.join("_")}\` ON \`${table}\` (${cols.join(", ")})${where ? " WHERE " + where : ""}`

migrate(
  (app) => {
    // Rules can refer to collections created later, so they are applied in a final pass.
    const pending = []
    const save = (c) => {
      const copy = (v) => (v === null || v === undefined ? null : String(v))
      pending.push([String(c.name), { listRule: copy(c.listRule), viewRule: copy(c.viewRule), createRule: copy(c.createRule), updateRule: copy(c.updateRule) }])
      c.listRule = c.viewRule = c.createRule = c.updateRule = null
      app.save(c)
      return c
    }
    const users = app.findCollectionByNameOrId("users")
    const rel = (name, collection, extra = {}) => ({
      type: "relation", name, collectionId: collection.id, maxSelect: 1, ...extra,
    })

    // coach_grants
    const grants = new Collection({
      type: "base",
      name: "coach_grants",
      listRule: `athlete = ${ME} || (coach = ${ME} && deleted = false)`,
      viewRule: `athlete = ${ME} || (coach = ${ME} && deleted = false)`,
      createRule: `@request.body.athlete = ${ME} && @request.body.coach != ${ME}`,
      updateRule: `athlete = ${ME} && ${unchanged("athlete", "coach")}`,
      deleteRule: null,
      fields: sync([
        rel("athlete", users, { required: true }),
        rel("coach", users, { required: true }),
      ]),
      indexes: [idx("coach_grants", ["athlete", "coach"], true), idx("coach_grants", ["coach", "updated"])],
    })
    save(grants)

    // users can see themselves and the people they are linked to through a grant
    const userView =
      `id = ${ME} || (@collection.coach_grants.athlete ?= id && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)` +
      ` || (@collection.coach_grants.coach ?= id && @collection.coach_grants.athlete ?= ${ME} && @collection.coach_grants.deleted ?= false)`

    // plans
    const plans = new Collection({
      type: "base",
      name: "plans",
      listRule: `owner = ${ME} || (deleted = false && ${planReadable("id", "owner", "visibility")})`,
      viewRule: `owner = ${ME} || (deleted = false && ${planReadable("id", "owner", "visibility")})`,
      createRule: `@request.body.owner = ${ME}`,
      updateRule: `owner = ${ME} && ${unchanged("owner")}`,
      deleteRule: null,
      fields: sync([
        rel("owner", users, { required: true }),
        { type: "text", name: "title", required: true, max: 200 },
        { type: "text", name: "description", max: 5000 },
        { type: "select", name: "visibility", required: true, maxSelect: 1, values: ["private", "public"] },
      ]),
      indexes: [idx("plans", ["owner", "updated"])],
    })
    save(plans)
    // self relation added after the collection exists
    plans.fields.add(new RelationField({ name: "source_plan", collectionId: plans.id, maxSelect: 1 }))
    app.save(plans)

    // plan_shares
    save(new Collection({
      type: "base",
      name: "plan_shares",
      listRule: `plan.owner = ${ME} || (user = ${ME} && deleted = false)`,
      viewRule: `plan.owner = ${ME} || (user = ${ME} && deleted = false)`,
      createRule: `@request.body.plan.owner = ${ME}`,
      updateRule: `plan.owner = ${ME} && ${unchanged("plan", "user")}`,
      deleteRule: null,
      fields: sync([
        rel("plan", plans, { required: true, cascadeDelete: true }),
        rel("user", users, { required: true, cascadeDelete: true }),
      ]),
      indexes: [idx("plan_shares", ["plan", "user"], true), idx("plan_shares", ["user", "updated"])],
    }))

    // workouts
    const workoutRead = `plan.owner = ${ME} || (deleted = false && plan.deleted = false && ${planReadable("plan", "plan.owner", "plan.visibility")})`
    save(new Collection({
      type: "base",
      name: "workouts",
      listRule: workoutRead,
      viewRule: workoutRead,
      createRule: `@request.body.plan.owner = ${ME}`,
      updateRule: `plan.owner = ${ME} && ${unchanged("plan")}`,
      deleteRule: null,
      fields: sync([
        rel("plan", plans, { required: true, cascadeDelete: true }),
        { type: "number", name: "day_index", min: 0, onlyInt: true },
        { type: "number", name: "position", min: 0, onlyInt: true },
        { type: "text", name: "title", required: true, max: 200 },
        {
          type: "select", name: "kind", required: true, maxSelect: 1,
          values: ["easy", "long", "tempo", "interval", "race", "rest", "cross", "strength"],
        },
        { type: "text", name: "description", max: 5000 },
        { type: "number", name: "distance_m", min: 0 },
        { type: "number", name: "duration_s", min: 0, onlyInt: true },
        { type: "json", name: "steps", maxSize: 100000 },
      ]),
      indexes: [idx("workouts", ["plan", "day_index"]), idx("workouts", ["plan", "updated"])],
    }))
    const workouts = app.findCollectionByNameOrId("workouts")

    // assignments
    const assignments = new Collection({
      type: "base",
      name: "assignments",
      listRule: `athlete = ${ME} || (deleted = false && ${coachOf("athlete")})`,
      viewRule: `athlete = ${ME} || (deleted = false && ${coachOf("athlete")})`,
      createRule:
        `@request.body.assigned_by = ${ME} && (@request.body.athlete = ${ME} || ${coachOf("@request.body.athlete")})` +
        ` && (@request.body.plan.owner = ${ME} || @request.body.plan.visibility = "public")`,
      updateRule: `(athlete = ${ME} || assigned_by = ${ME}) && ${unchanged("plan", "athlete", "assigned_by")}`,
      deleteRule: null,
      fields: sync([
        rel("plan", plans, { required: true, cascadeDelete: true }),
        rel("athlete", users, { required: true, cascadeDelete: true }),
        rel("assigned_by", users, { required: true }),
        { type: "text", name: "start_date", required: true, pattern: "^\\d{4}-\\d{2}-\\d{2}$" },
      ]),
      indexes: [idx("assignments", ["athlete", "updated"]), idx("assignments", ["plan", "athlete"])],
    })
    save(assignments)

    // activities: clients write only fit/manual rows; hooks write strava/garmin rows
    const activities = new Collection({
      type: "base",
      name: "activities",
      listRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      viewRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      createRule: `@request.body.owner = ${ME} && (@request.body.source = "fit" || @request.body.source = "manual")`,
      updateRule: `owner = ${ME} && (source = "fit" || source = "manual") && ${unchanged("owner", "source")}`,
      deleteRule: null,
      fields: sync([
        rel("owner", users, { required: true, cascadeDelete: true }),
        { type: "select", name: "source", required: true, maxSelect: 1, values: ["strava", "fit", "manual", "garmin"] },
        { type: "text", name: "external_id", max: 200 },
        { type: "date", name: "started_at", required: true },
        {
          type: "select", name: "sport", required: true, maxSelect: 1,
          values: ["run", "trail_run", "walk", "hike", "ride", "swim", "strength", "other"],
        },
        { type: "text", name: "name", max: 200 },
        { type: "number", name: "distance_m", min: 0 },
        { type: "number", name: "moving_time_s", min: 0, onlyInt: true },
        { type: "number", name: "elapsed_time_s", min: 0, onlyInt: true },
        { type: "number", name: "elevation_gain_m", min: 0 },
        { type: "number", name: "avg_hr", min: 0, onlyInt: true },
        { type: "number", name: "max_hr", min: 0, onlyInt: true },
        { type: "json", name: "laps", maxSize: 500000 },
      ]),
      indexes: [
        idx("activities", ["owner", "updated"]),
        idx("activities", ["owner", "started_at"]),
        idx("activities", ["owner", "source", "external_id"], true, "external_id != ''"),
      ],
    })
    save(activities)

    // matches
    save(new Collection({
      type: "base",
      name: "matches",
      listRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      viewRule: `owner = ${ME} || (deleted = false && ${coachOf("owner")})`,
      createRule:
        `@request.body.owner = ${ME} && @request.body.activity.owner = ${ME} && @request.body.assignment.athlete = ${ME}`,
      updateRule: `owner = ${ME} && ${unchanged("owner", "activity", "assignment")}`,
      deleteRule: null,
      fields: sync([
        rel("owner", users, { required: true, cascadeDelete: true }),
        rel("activity", activities, { required: true, cascadeDelete: true }),
        rel("assignment", assignments, { required: true, cascadeDelete: true }),
        rel("workout", workouts, { required: true }),
      ]),
      indexes: [idx("matches", ["activity"], true), idx("matches", ["owner", "updated"])],
    }))

    // strava_connections: no API rules, so only hooks and superusers can use it
    save(new Collection({
      type: "base",
      name: "strava_connections",
      listRule: null,
      viewRule: null,
      createRule: null,
      updateRule: null,
      deleteRule: null,
      fields: [
        rel("user", users, { required: true, cascadeDelete: true }),
        { type: "number", name: "strava_athlete_id", required: true, onlyInt: true },
        { type: "text", name: "access_token", required: true },
        { type: "text", name: "refresh_token", required: true },
        { type: "date", name: "expires_at", required: true },
        { type: "text", name: "scope", max: 500 },
        { type: "autodate", name: "created", onCreate: true },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
      ],
      indexes: [idx("strava_connections", ["user"], true), idx("strava_connections", ["strava_athlete_id"], true)],
    }))

    for (const [name, rules] of pending) {
      const c = app.findCollectionByNameOrId(name)
      c.listRule = rules.listRule
      c.viewRule = rules.viewRule
      c.createRule = rules.createRule
      c.updateRule = rules.updateRule
      app.save(c)
    }
    users.listRule = userView
    users.viewRule = userView
    app.save(users)
  },
  (app) => {
    for (const name of ["strava_connections", "matches", "activities", "assignments", "workouts", "plan_shares", "plans", "coach_grants"]) {
      app.delete(app.findCollectionByNameOrId(name))
    }
    const users = app.findCollectionByNameOrId("users")
    users.listRule = "id = @request.auth.id"
    users.viewRule = "id = @request.auth.id"
    app.save(users)
  },
)
