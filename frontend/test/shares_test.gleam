import atlas/shares.{Share}
import gleam/option.{None, Some}

fn share(
  id: String,
  plan: String,
  user: String,
  name: String,
  by: String,
  deleted: Bool,
) -> shares.Share {
  Share(id, plan, user, name, by, deleted, "T-" <> id)
}

fn all() -> List(shares.Share) {
  [
    share("s1", "p1", "bob", "Bob", "Ana", False),
    share("s2", "p1", "carl", "carl", "Ana", False),
    share("s3", "p1", "dora", "Dora", "Ana", True),
    share("s4", "p2", "bob", "Bob", "Eve", False),
  ]
}

fn ids(items: List(shares.Share)) -> List(String) {
  case items {
    [] -> []
    [s, ..rest] -> [s.id, ..ids(rest)]
  }
}

pub fn the_current_shares_of_a_plan_are_sorted_by_name_and_skip_removed_ones_test() {
  assert ids(shares.current_for(all(), "p1")) == ["s1", "s2"]
  assert ids(shares.current_for(all(), "p2")) == ["s4"]
  assert shares.current_for(all(), "nope") == []
}

pub fn sharing_is_per_plan_and_per_person_and_ends_when_removed_test() {
  assert shares.is_shared_with(all(), "p1", "bob")
  assert !shares.is_shared_with(all(), "p1", "dora")
  assert !shares.is_shared_with(all(), "p2", "carl")
  assert !shares.is_shared_with(all(), "p1", "nobody")
}

pub fn the_row_is_found_even_when_removed_so_it_can_be_reused_test() {
  let assert Some(removed) = shares.row_for(all(), "p1", "dora")
  assert removed.id == "s3"
  assert removed.deleted
  assert shares.row_for(all(), "p1", "nobody") == None
}

pub fn the_recipient_sees_who_shared_the_plan_test() {
  assert shares.shared_by(all(), "p1", "bob") == Some("Ana")
  assert shares.shared_by(all(), "p2", "bob") == Some("Eve")
  assert shares.shared_by(all(), "p1", "dora") == None
  assert shares.shared_by(all(), "p1", "stranger") == None
  assert shares.shared_by(
      [share("s", "p", "bob", "Bob", "  ", False)],
      "p",
      "bob",
    )
    == Some("someone")
}
