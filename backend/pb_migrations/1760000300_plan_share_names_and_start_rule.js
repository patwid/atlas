/// <reference path="../pb_data/types.d.ts" />
// 1. Display names on plan shares, so a device can say "Shared by Ana" and list who a plan is shared with
//    without the users collection (labels only, like the names on coach grants).
// 2. A plan shared with someone can be started by them (an assignment for themselves or, as a coach, for an
//    athlete), not only plans they own or public ones. See docs/adr/0029-sharing-plans.md.
const ME = "@request.auth.id"

const coachOf = (athleteExpr) =>
  `(@collection.coach_grants.athlete ?= ${athleteExpr} && @collection.coach_grants.coach ?= ${ME} && @collection.coach_grants.deleted ?= false)`

const sharedWithMe = (planExpr) =>
  `(@collection.plan_shares.plan ?= ${planExpr} && @collection.plan_shares.user ?= ${ME} && @collection.plan_shares.deleted ?= false)`

const createRule = (withShares) =>
  `@request.body.assigned_by = ${ME} && (@request.body.athlete = ${ME} || ${coachOf("@request.body.athlete")})` +
  ` && (@request.body.plan.owner = ${ME} || @request.body.plan.visibility = "public"` +
  (withShares ? ` || ${sharedWithMe("@request.body.plan")}` : "") +
  `)`

migrate(
  (app) => {
    const shares = app.findCollectionByNameOrId("plan_shares")
    shares.fields.add(new TextField({ name: "user_name", max: 200 }))
    shares.fields.add(new TextField({ name: "shared_by_name", max: 200 }))
    app.save(shares)

    const assignments = app.findCollectionByNameOrId("assignments")
    assignments.createRule = createRule(true)
    app.save(assignments)
  },
  (app) => {
    const shares = app.findCollectionByNameOrId("plan_shares")
    shares.fields.removeByName("user_name")
    shares.fields.removeByName("shared_by_name")
    app.save(shares)

    const assignments = app.findCollectionByNameOrId("assignments")
    assignments.createRule = createRule(false)
    app.save(assignments)
  },
)
