import atlas/collection.{Matches, Plans, Workouts}
import atlas/conflict
import atlas/id
import atlas/local
import atlas/outbox
import atlas/sync
import atlas/syncing.{type Context, Context, State}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}

// A token that expires at 1791707435 (see auth_test).
const token =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJjb2xsZWN0aW9uSWQiOiJfcGJfdXNlcnNfYXV0aF8iLCJleHAiOjE3OTE3MDc0MzUsImlkIjoidXNlcjEyMyIsInR5cGUiOiJhdXRoIn0.sig"

const before_expiry = 1_791_000_000

const after_expiry = 1_792_000_000

fn context(now: Int) -> Context {
  Context(token, now, 120)
}

fn dynamic_of(text: String) -> Dynamic {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn ready() -> syncing.State {
  let #(state, _, _) =
    syncing.update(
      syncing.new(),
      syncing.Loaded(Ok(local.Loaded(outbox.new(), []))),
      context(before_expiry),
    )
  state
}

fn outbox_of(state: syncing.State) -> outbox.Outbox {
  let assert Some(engine) = state.sync
  sync.outbox(engine)
}

fn title(value: String) -> outbox.Fields {
  dict.from_list([outbox.field_string("title", value)])
}

pub fn loading_the_device_data_makes_the_state_ready_and_starts_a_run_test() {
  let state = ready()
  assert syncing.is_ready(state)
  let assert Some(engine) = state.sync
  assert sync.is_busy(engine)
}

pub fn an_expired_token_asks_for_sign_in_instead_of_starting_a_run_test() {
  let #(state, _, notices) =
    syncing.update(
      syncing.new(),
      syncing.Loaded(Ok(local.Loaded(outbox.new(), []))),
      context(after_expiry),
    )
  assert syncing.is_ready(state)
  assert notices == [sync.SignInRequired]
}

pub fn an_unreadable_device_database_stops_everything_test() {
  let #(state, _, notices) =
    syncing.update(
      syncing.new(),
      syncing.Loaded(Error(Nil)),
      context(before_expiry),
    )
  assert state.phase == syncing.Unavailable
  assert state.sync == None
  assert notices == []
  // Nothing can be written then, so no change is accepted silently.
  let #(after, _) = syncing.create(state, Plans, "p1", title("A"))
  assert after.sync == None
}

pub fn kicking_before_loading_does_nothing_test() {
  let #(state, _, notices) =
    syncing.update(syncing.new(), syncing.Kick, context(before_expiry))
  assert state == syncing.new()
  assert notices == []
}

pub fn a_local_create_is_queued_in_the_outbox_test() {
  let #(state, _) = syncing.create(ready(), Plans, "p1", title("New plan"))
  assert outbox.has_pending(outbox_of(state), Plans, "p1")
  assert outbox.pending_count(outbox_of(state)) == 1
}

pub fn a_local_edit_merges_into_an_unsent_create_test() {
  let #(state, _) = syncing.create(ready(), Plans, "p1", title("A"))
  let #(state, _) = syncing.edit(state, Plans, "p1", title("B"), "ignored")
  assert outbox.pending_count(outbox_of(state)) == 1
}

pub fn a_local_delete_of_an_unsent_create_cancels_it_test() {
  let #(state, _) = syncing.create(ready(), Plans, "p1", title("A"))
  let #(state, _) = syncing.delete(state, Plans, "p1", "ignored")
  assert outbox.is_empty(outbox_of(state))
}

pub fn a_local_delete_of_a_synced_record_is_a_soft_delete_update_test() {
  let #(state, _) = syncing.delete(ready(), Plans, "p1", "T1")
  let assert [entry] = outbox_of(state).entries
  assert entry.kind == outbox.Update
  assert entry.fields == dict.from_list([outbox.field_bool("deleted", True)])
  assert entry.base_updated == Some("T1")
}

pub fn writes_are_refused_before_the_device_data_is_loaded_test() {
  let #(state, _) = syncing.create(syncing.new(), Plans, "p1", title("A"))
  assert state == syncing.new()
}

const local_plan =
  "{\"id\":\"p1\",\"title\":\"10k plan\",\"owner\":\"u1\",\"visibility\":\"private\",\"description\":\"\",\"updated\":\"2026-10-06 08:00:00.100Z\",\"deleted\":false}"

pub fn a_conflicting_plan_edit_is_kept_as_a_copy_and_explained_test() {
  let #(state, _, _) =
    syncing.update(
      ready(),
      syncing.LocalVersion(Plans, "p1", Ok(Some(dynamic_of(local_plan)))),
      context(before_expiry),
    )
  let assert [entry] = outbox_of(state).entries
  assert entry.kind == outbox.Create
  assert entry.collection == Plans
  assert entry.id != "p1"
  assert id.is_valid(entry.id)
  assert entry.fields
    == dict.from_list([
      outbox.field_string("title", "10k plan" <> conflict.copy_suffix),
      #("description", "\"\""),
      #("owner", "\"u1\""),
      #("visibility", "\"private\""),
    ])
  let assert [message] = state.problems
  assert message
    == "A change to \"10k plan\" clashed with a newer one made elsewhere. Your version was kept as \"10k plan (conflicted copy)\"."
}

pub fn a_conflict_on_a_workout_keeps_its_plan_relation_test() {
  let workout =
    "{\"id\":\"w1\",\"plan\":\"p1\",\"title\":\"Tempo\",\"kind\":\"tempo\",\"day_index\":3,\"updated\":\"x\",\"deleted\":false}"
  let #(state, _, _) =
    syncing.update(
      ready(),
      syncing.LocalVersion(Workouts, "w1", Ok(Some(dynamic_of(workout)))),
      context(before_expiry),
    )
  let assert [entry] = outbox_of(state).entries
  assert entry.collection == Workouts
  assert dict.get(entry.fields, "plan") == Ok("\"p1\"")
  assert dict.get(entry.fields, "day_index") == Ok("3")
}

pub fn a_conflicting_delete_is_not_copied_test() {
  let deleted = "{\"id\":\"p1\",\"title\":\"x\",\"deleted\":true}"
  let #(state, _, _) =
    syncing.update(
      ready(),
      syncing.LocalVersion(Plans, "p1", Ok(Some(dynamic_of(deleted)))),
      context(before_expiry),
    )
  assert outbox.is_empty(outbox_of(state))
  assert list.length(state.problems) == 1
}

pub fn a_conflict_on_something_not_copyable_only_reports_test() {
  let #(state, _, _) =
    syncing.update(
      ready(),
      syncing.LocalVersion(
        Matches,
        "m1",
        Ok(Some(dynamic_of("{\"id\":\"m1\"}"))),
      ),
      context(before_expiry),
    )
  assert outbox.is_empty(outbox_of(state))
  assert list.length(state.problems) == 1
}

pub fn a_missing_local_version_changes_nothing_but_fetches_the_server_one_test() {
  let #(state, _, _) =
    syncing.update(
      ready(),
      syncing.LocalVersion(Plans, "p1", Ok(None)),
      context(before_expiry),
    )
  assert outbox.is_empty(outbox_of(state))
  assert state.problems == []
}

pub fn problems_can_be_dismissed_test() {
  let with_problem = State(..ready(), problems: ["a", "b"])
  assert syncing.dismiss_problems(with_problem).problems == []
}

pub fn a_failed_storage_write_is_remembered_test() {
  let #(state, _, _) =
    syncing.update(ready(), syncing.Wrote(False), context(before_expiry))
  assert state.write_failed
  let #(ok, _, _) =
    syncing.update(ready(), syncing.Wrote(True), context(before_expiry))
  assert !ok.write_failed
}

pub fn reset_forgets_the_loaded_state_test() {
  let state = syncing.reset(ready())
  assert state.phase == syncing.NotLoaded
  assert state.sync == None
}
