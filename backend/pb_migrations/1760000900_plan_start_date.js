/// <reference path="../pb_data/types.d.ts" />
// A plan's own start date, which the assignments made by its owner follow, and workouts counted from the Monday of the
// plan's first week. See docs/adr/0108-plan-start-date.md.
//
// 1. `plans.start_date` (YYYY-MM-DD, empty for none). Once set it cannot be emptied: assignments may follow it.
// 2. `assignments.start_date` may be empty: the assignment follows its plan's start date, which must then be set.
// 3. Existing data keeps its dates: a plan that is followed gets the start date of one of its assignments, and its
//    workouts move by that day's weekday, since `day_index` 0 is now that week's Monday rather than the start day.
const DATE_OR_EMPTY = "^(\\d{4}-\\d{2}-\\d{2})?$"
const DATE = "^\\d{4}-\\d{2}-\\d{2}$"

const PLAN_KEEPS_DATE = `(start_date = "" || @request.body.start_date:isset = false || @request.body.start_date != "")`
const FOLLOWS_A_DATED_PLAN = `(@request.body.start_date != "" || @request.body.plan.start_date != "")`
const STAYS_ON_A_DATED_PLAN = `(@request.body.start_date:isset = false || @request.body.start_date != "" || plan.start_date != "")`

const withClause = (rule, clause) => `(${rule}) && ${clause}`
const withoutClause = (rule, clause) => {
  const suffix = `) && ${clause}`
  return rule.startsWith("(") && rule.endsWith(suffix) ? rule.slice(1, -suffix.length) : rule
}

/// Monday 0 to Sunday 6.
const weekdayOf = (ymd) => (new Date(`${ymd}T00:00:00Z`).getUTCDay() + 6) % 7

migrate(
  (app) => {
    const plans = app.findCollectionByNameOrId("plans")
    plans.fields.add(new TextField({ name: "start_date", pattern: DATE_OR_EMPTY }))
    plans.updateRule = withClause(plans.updateRule, PLAN_KEEPS_DATE)
    app.save(plans)

    const assignments = app.findCollectionByNameOrId("assignments")
    const start = assignments.fields.getByName("start_date")
    start.required = false
    start.pattern = DATE_OR_EMPTY
    assignments.createRule = withClause(assignments.createRule, FOLLOWS_A_DATED_PLAN)
    assignments.updateRule = withClause(assignments.updateRule, STAYS_ON_A_DATED_PLAN)
    app.save(assignments)

    // The plan's date: an assignment of its owner for themselves, else one its owner made, else any; the latest.
    const live = app.findRecordsByFilter("assignments", "deleted = false", "", 0, 0)
    const byPlan = new Map()
    for (const a of live) {
      const planId = a.getString("plan")
      byPlan.set(planId, [...(byPlan.get(planId) ?? []), a])
    }
    for (const [planId, rows] of byPlan) {
      const plan = app.findRecordById("plans", planId)
      const owner = plan.getString("owner")
      const rank = (a) => (a.getString("assigned_by") === owner ? (a.getString("athlete") === owner ? 0 : 1) : 2)
      const chosen = [...rows].sort((a, b) =>
        rank(a) - rank(b) || b.getString("start_date").localeCompare(a.getString("start_date")))[0]
      const startDate = chosen.getString("start_date")
      if (!new RegExp(DATE).test(startDate)) continue

      const shift = weekdayOf(startDate)
      if (shift > 0) {
        for (const w of app.findRecordsByFilter("workouts", "plan = {:plan}", "", 0, 0, { plan: planId })) {
          w.set("day_index", w.getInt("day_index") + shift)
          app.save(w)
        }
      }
      plan.set("start_date", startDate)
      app.save(plan)
      // The owner's assignments on that date follow the plan from now on.
      for (const a of rows) {
        if (a.getString("assigned_by") === owner && a.getString("start_date") === startDate) {
          a.set("start_date", "")
          app.save(a)
        }
      }
    }
  },
  (app) => {
    // Give following assignments their plan's date back and undo the shift of the workouts.
    for (const plan of app.findRecordsByFilter("plans", `start_date != ""`, "", 0, 0)) {
      const startDate = plan.getString("start_date")
      for (const a of app.findRecordsByFilter("assignments", `plan = {:plan} && start_date = ""`, "", 0, 0, { plan: plan.id })) {
        a.set("start_date", startDate)
        app.save(a)
      }
      const shift = weekdayOf(startDate)
      if (shift > 0) {
        for (const w of app.findRecordsByFilter("workouts", "plan = {:plan}", "", 0, 0, { plan: plan.id })) {
          w.set("day_index", Math.max(0, w.getInt("day_index") - shift))
          app.save(w)
        }
      }
    }

    const assignments = app.findCollectionByNameOrId("assignments")
    const start = assignments.fields.getByName("start_date")
    start.required = true
    start.pattern = DATE
    assignments.createRule = withoutClause(assignments.createRule, FOLLOWS_A_DATED_PLAN)
    assignments.updateRule = withoutClause(assignments.updateRule, STAYS_ON_A_DATED_PLAN)
    app.save(assignments)

    const plans = app.findCollectionByNameOrId("plans")
    plans.fields.removeByName("start_date")
    plans.updateRule = withoutClause(plans.updateRule, PLAN_KEEPS_DATE)
    app.save(plans)
  },
)
