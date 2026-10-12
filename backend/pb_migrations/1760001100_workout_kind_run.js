/// <reference path="../pb_data/types.d.ts" />
// One kind for every run: easy, long and tempo runs become `run`, and cross-training and strength workouts are gone,
// so they become runs too. See docs/adr/0114-one-kind-for-every-run.md.
//
// The rows are changed in SQL, without moving `updated`: devices are not made to pull them again, and a change made
// offline to one of them is not refused as a conflict. Apps read the old kinds as a run (`plan.kind_from_string`), and
// `pb_hooks/workout_kind.pb.js` turns an old kind sent by an app not yet updated into `run`.
const OLD = ["easy", "long", "tempo", "cross", "strength"]
const BEFORE = ["easy", "long", "tempo", "interval", "race", "rest", "cross", "strength"]
const AFTER = ["run", "interval", "race", "rest"]

const setValues = (app, values) => {
  const workouts = app.findCollectionByNameOrId("workouts")
  workouts.fields.getByName("kind").values = values
  app.save(workouts)
}

migrate(
  (app) => {
    app.db().newQuery(`UPDATE workouts SET kind = 'run' WHERE kind IN (${OLD.map((k) => `'${k}'`).join(", ")})`).execute()
    setValues(app, AFTER)
  },
  (app) => {
    // Which runs were easy, long or tempo, cross-training or strength is lost: they all go back as easy runs.
    setValues(app, BEFORE)
    app.db().newQuery("UPDATE workouts SET kind = 'easy' WHERE kind = 'run'").execute()
  },
)
