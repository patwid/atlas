/// <reference path="../pb_data/types.d.ts" />
// Plan phases, a weekly distance goal and the intensity of each week, on plans. Not required, so rows saved before
// and app versions that do not know them keep working; a plan with no phase weeks is shown as before.
// See docs/adr/0043-plan-phases-goal-and-calendar.md.
const WEEKS = ["base_weeks", "pre_competition_weeks", "competition_weeks"]

migrate(
  (app) => {
    const plans = app.findCollectionByNameOrId("plans")
    for (const name of WEEKS) plans.fields.add(new NumberField({ name, min: 0, max: 52, onlyInt: true }))
    // metres, up to 1000 km
    plans.fields.add(new NumberField({ name: "weekly_distance_m", min: 0, max: 1000000 }))
    // one level per week in week order, "" for none: ["", "high"] makes week 2 hard ("low", "medium" or "high")
    plans.fields.add(new JSONField({ name: "week_intensity", maxSize: 10000 }))
    app.save(plans)
  },
  (app) => {
    const plans = app.findCollectionByNameOrId("plans")
    for (const name of [...WEEKS, "weekly_distance_m", "week_intensity"]) plans.fields.removeByName(name)
    app.save(plans)
  },
)
