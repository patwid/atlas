// A workout kind from before there was one kind for every run (easy, long, tempo, cross, strength) is saved as `run`,
// so an app not yet updated, or a change it queued offline, is not refused. Superusers save what they send.
// See docs/adr/0114-one-kind-for-every-run.md.
const toRun = (e) => {
  if (!e.hasSuperuserAuth() && ["easy", "long", "tempo", "cross", "strength"].includes(e.record.getString("kind"))) e.record.set("kind", "run")
  return e.next()
}
onRecordCreateRequest(toRun, "workouts")
onRecordUpdateRequest(toRun, "workouts")
