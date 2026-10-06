import atlas/collection.{Matches, Plans, Workouts}
import atlas/conflict
import atlas/outbox
import gleam/dict
import gleam/option.{None, Some}

fn stored() -> List(#(String, String)) {
  [
    #("id", "\"p1\""),
    #("title", "\"10k plan\""),
    #("description", "\"Build up\""),
    #("owner", "\"u1\""),
    #("visibility", "\"private\""),
    #("updated", "\"2026-10-06 08:00:00.100Z\""),
    #("created", "\"2026-10-01 08:00:00.100Z\""),
    #("collectionId", "\"pbc_1\""),
    #("collectionName", "\"plans\""),
    #("deleted", "false"),
  ]
}

pub fn only_hand_written_records_are_copied_test() {
  assert conflict.copyable(Plans)
  assert conflict.copyable(Workouts)
  assert !conflict.copyable(Matches)
  assert !conflict.copyable(collection.Activities)
  assert !conflict.copyable(collection.CoachGrants)
  assert !conflict.copyable(collection.Assignments)
}

pub fn the_copy_drops_server_fields_and_marks_the_title_test() {
  let assert Some(fields) = conflict.copy_fields(Plans, stored())
  assert fields
    == dict.from_list([
      outbox.field_string("title", "10k plan (conflicted copy)"),
      #("description", "\"Build up\""),
      #("owner", "\"u1\""),
      #("visibility", "\"private\""),
    ])
}

pub fn a_deleted_or_uncopyable_record_has_no_copy_test() {
  let deleted = [#("id", "\"p1\""), #("title", "\"x\""), #("deleted", "true")]
  assert conflict.copy_fields(Plans, deleted) == None
  assert conflict.copy_fields(Matches, stored()) == None
}

pub fn titles_with_quotes_survive_test() {
  let tricky = [#("title", "\"A \\\"quoted\\\" plan\"")]
  let assert Some(fields) = conflict.copy_fields(Plans, tricky)
  assert fields
    == dict.from_list([
      outbox.field_string("title", "A \"quoted\" plan (conflicted copy)"),
    ])
  assert conflict.title_of(tricky) == "A \"quoted\" plan"
  assert conflict.title_of([]) == ""
}
