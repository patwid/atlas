/// <reference path="../pb_data/types.d.ts" />
// Every plan is for one athlete, chosen when it is made and fixed from then on; sharing and public plans are gone.
// See docs/adr/0110-one-athlete-per-plan.md.
//
// 1. Existing data is split: a plan keeps one assignment its owner made (their own first), and every other live
//    assignment moves to a copy of the plan, owned by whoever made that assignment, with its matches moved to the
//    copy's workouts. A plan nobody follows gets one for its owner. Every assignment then follows its plan's date.
// 2. `assignments`: one per plan (unique), made only by the plan's owner, readable by the owner too, never changed.
// 3. `plans` and `workouts` are readable by the owner and the plan's athlete; `plans.visibility` and the
//    `plan_shares` collection are removed.
const ME = "@request.auth.id"

const coachOf = (athleteExpr) =>
  `(@collection.coach_grants.athlete ?= ${athleteExpr} && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)`
const unchanged = (...fields) => fields.map((f) => `@request.body.${f}:changed = false`).join(" && ")

// The plan's athlete can read it, as before through the assignment.
const assignedToMe = (planExpr) =>
  `(@collection.assignments.plan ?= ${planExpr} && @collection.assignments.athlete ?= ${ME} && @collection.assignments.deleted ?= false)`

const RULES = {
  plans: {
    read: `owner = ${ME} || (deleted = false && ${assignedToMe("id")})`,
  },
  workouts: {
    read: `plan.owner = ${ME} || (deleted = false && plan.deleted = false && ${assignedToMe("plan")})`,
  },
  assignments: {
    read: `athlete = ${ME} || plan.owner = ${ME} || (deleted = false && ${coachOf("athlete")})`,
    create:
      `@request.body.assigned_by = ${ME} && @request.body.plan.owner = ${ME}` +
      ` && (@request.body.athlete = ${ME} || ${coachOf("@request.body.athlete")})` +
      ` && (@request.body.start_date:isset = false || @request.body.start_date = "")`,
    update: null,
  },
}

// The rules before this migration (1760000000, 0300 and 0900), for going back.
const sharedWithMe = (planExpr) =>
  `(@collection.plan_shares.plan ?= ${planExpr} && @collection.plan_shares.user ?= ${ME} && @collection.plan_shares.deleted ?= false)`
const planReadable = (planExpr, ownerExpr, visibilityExpr) =>
  `(${ownerExpr} = ${ME} || (${visibilityExpr} = "public" && ${ME} != "")` +
  ` || ${sharedWithMe(planExpr)}` +
  ` || ${assignedToMe(planExpr)})`
const BEFORE = {
  plans: {
    read: `owner = ${ME} || (deleted = false && ${planReadable("id", "owner", "visibility")})`,
  },
  workouts: {
    read: `plan.owner = ${ME} || (deleted = false && plan.deleted = false && ${planReadable("plan", "plan.owner", "plan.visibility")})`,
  },
  assignments: {
    read: `athlete = ${ME} || (deleted = false && ${coachOf("athlete")})`,
    create:
      `(@request.body.assigned_by = ${ME} && (@request.body.athlete = ${ME} || ${coachOf("@request.body.athlete")})` +
      ` && (@request.body.plan.owner = ${ME} || @request.body.plan.visibility = "public" || ${sharedWithMe("@request.body.plan")}))` +
      ` && (@request.body.start_date != "" || @request.body.plan.start_date != "")`,
    update:
      `((athlete = ${ME} || assigned_by = ${ME}) && ${unchanged("plan", "athlete", "assigned_by")})` +
      ` && (@request.body.start_date:isset = false || @request.body.start_date != "" || plan.start_date != "")`,
  },
}

const ONE_PER_PLAN = "CREATE UNIQUE INDEX `idx_assignments_plan` ON `assignments` (`plan`)"

/// Every field of a record but its ID and timestamps, to copy it.
const copyFields = (app, collectionName, from, to) => {
  for (const field of app.findCollectionByNameOrId(collectionName).fields) {
    if (["id", "created", "updated"].includes(field.name)) continue
    to.set(field.name, from.get(field.name))
  }
}

/// A copy of the plan and all its workouts (removed ones too, which matches may point at), for one assignment.
const splitOff = (app, plan, assignment) => {
  const copy = new Record(app.findCollectionByNameOrId("plans"))
  copyFields(app, "plans", plan, copy)
  copy.set("owner", assignment.getString("assigned_by"))
  copy.set("source_plan", plan.id)
  copy.set("visibility", "private")
  copy.set("start_date", assignment.getString("start_date") || plan.getString("start_date"))
  app.save(copy)

  const workouts = app.findCollectionByNameOrId("workouts")
  const moved = new Map()
  for (const w of app.findRecordsByFilter("workouts", "plan = {:plan}", "", 0, 0, { plan: plan.id })) {
    const wc = new Record(workouts)
    copyFields(app, "workouts", w, wc)
    wc.set("plan", copy.id)
    app.save(wc)
    moved.set(w.id, wc.id)
  }

  assignment.set("plan", copy.id)
  assignment.set("start_date", "")
  app.save(assignment)
  for (const m of app.findRecordsByFilter("matches", "assignment = {:a}", "", 0, 0, { a: assignment.id })) {
    const workout = moved.get(m.getString("workout"))
    if (workout) {
      m.set("workout", workout)
      app.save(m)
    }
  }
}

migrate(
  (app) => {
    // A removed assignment would only be purged (its matches with it); there is now no other way to have one.
    for (const a of app.findRecordsByFilter("assignments", "deleted = true", "", 0, 0)) app.delete(a)

    const assignments = app.findCollectionByNameOrId("assignments")
    for (const plan of app.findRecordsByFilter("plans", "", "", 0, 0)) {
      const owner = plan.getString("owner")
      const live = app.findRecordsByFilter("assignments", "plan = {:plan}", "", 0, 0, { plan: plan.id })
      // The owner's own first, then one following the plan, then the latest start.
      const rank = (a) => (a.getString("athlete") === owner ? 0 : 1)
      const ownerMade = live
        .filter((a) => a.getString("assigned_by") === owner)
        .sort((a, b) =>
          rank(a) - rank(b) ||
          (a.getString("start_date") === "" ? 0 : 1) - (b.getString("start_date") === "" ? 0 : 1) ||
          b.getString("start_date").localeCompare(a.getString("start_date")))
      const keep = ownerMade[0] ?? (plan.getBool("deleted") ? live[0] : undefined)
      for (const a of live) {
        if (a === keep) continue
        // A deleted plan is not split up: its other assignments go, as they would with the plan.
        if (plan.getBool("deleted")) app.delete(a)
        else splitOff(app, plan, a)
      }
      if (keep) {
        if (keep.getString("start_date") !== "") {
          // Workouts keep their weekday from the Monday of the start's week, so the schedule stays the same (0108).
          plan.set("start_date", keep.getString("start_date"))
          app.save(plan)
          keep.set("start_date", "")
          app.save(keep)
        }
      } else {
        const own = new Record(assignments)
        own.set("plan", plan.id)
        own.set("athlete", owner)
        own.set("assigned_by", owner)
        own.set("start_date", "")
        app.save(own)
      }
    }

    assignments.listRule = assignments.viewRule = RULES.assignments.read
    assignments.createRule = RULES.assignments.create
    assignments.updateRule = RULES.assignments.update
    assignments.indexes = [...assignments.indexes, ONE_PER_PLAN]
    app.save(assignments)

    const plans = app.findCollectionByNameOrId("plans")
    plans.listRule = plans.viewRule = RULES.plans.read
    plans.fields.removeByName("visibility")
    app.save(plans)

    const workouts = app.findCollectionByNameOrId("workouts")
    workouts.listRule = workouts.viewRule = RULES.workouts.read
    app.save(workouts)

    // Last, once no rule refers to it.
    app.delete(app.findCollectionByNameOrId("plan_shares"))
  },
  (app) => {
    // The split is not undone: the copies are plans of their own by now.
    const plans = app.findCollectionByNameOrId("plans")
    plans.fields.add(new SelectField({ name: "visibility", maxSelect: 1, values: ["private", "public"] }))
    app.save(plans)
    for (const plan of app.findRecordsByFilter("plans", "", "", 0, 0)) {
      plan.set("visibility", "private")
      app.save(plan)
    }
    plans.fields.getByName("visibility").required = true

    const users = app.findCollectionByNameOrId("users")
    app.save(new Collection({
      type: "base",
      name: "plan_shares",
      listRule: `plan.owner = ${ME} || (user = ${ME} && deleted = false)`,
      viewRule: `plan.owner = ${ME} || (user = ${ME} && deleted = false)`,
      createRule: `@request.body.plan.owner = ${ME}`,
      updateRule: `plan.owner = ${ME} && ${unchanged("plan", "user")}`,
      deleteRule: null,
      fields: [
        { type: "bool", name: "deleted" },
        { type: "autodate", name: "created", onCreate: true },
        { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
        { type: "relation", name: "plan", collectionId: plans.id, required: true, cascadeDelete: true, maxSelect: 1 },
        { type: "relation", name: "user", collectionId: users.id, required: true, cascadeDelete: true, maxSelect: 1 },
        { type: "text", name: "user_name", max: 200 },
        { type: "text", name: "shared_by_name", max: 200 },
      ],
      indexes: [
        "CREATE UNIQUE INDEX `idx_plan_shares_plan_user` ON `plan_shares` (plan, user)",
        "CREATE INDEX `idx_plan_shares_user_updated` ON `plan_shares` (user, updated)",
      ],
    }))

    plans.listRule = plans.viewRule = BEFORE.plans.read
    app.save(plans)

    const workouts = app.findCollectionByNameOrId("workouts")
    workouts.listRule = workouts.viewRule = BEFORE.workouts.read
    app.save(workouts)

    const assignments = app.findCollectionByNameOrId("assignments")
    assignments.listRule = assignments.viewRule = BEFORE.assignments.read
    assignments.createRule = BEFORE.assignments.create
    assignments.updateRule = BEFORE.assignments.update
    assignments.indexes = assignments.indexes.filter((i) => !i.includes("idx_assignments_plan`"))
    app.save(assignments)
  },
)
