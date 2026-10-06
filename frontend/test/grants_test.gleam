import atlas/grants.{Grant, Person}
import gleam/option.{None, Some}

fn grant(
  id: String,
  athlete: String,
  coach: String,
  athlete_name: String,
  coach_name: String,
) -> grants.Grant {
  Grant(id, athlete, coach, athlete_name, coach_name, "T")
}

fn all() -> List(grants.Grant) {
  [
    grant("g1", "ana", "me", "Ana", "Me Coach"),
    grant("g2", "ben", "me", "ben", "Me Coach"),
    grant("g3", "me", "carl", "Me Athlete", "Carl"),
    grant("g4", "me", "dora", "Me Athlete", "dora"),
    grant("g5", "eve", "other", "Eve", "Other Coach"),
  ]
}

pub fn the_athletes_of_a_coach_are_the_grants_made_to_them_by_name_test() {
  assert grants.athletes_of(all(), "me")
    == [Person("ana", "Ana"), Person("ben", "ben")]
  assert grants.athletes_of(all(), "nobody") == []
}

pub fn a_missing_name_still_gives_a_usable_entry_test() {
  let unnamed = [grant("g", "x", "me", "  ", "")]
  assert grants.athletes_of(unnamed, "me") == [Person("x", "Unnamed athlete")]
}

pub fn the_same_athlete_is_listed_once_test() {
  let twice = [
    grant("g1", "ana", "me", "Ana", ""),
    grant("g2", "ana", "me", "Ana", ""),
  ]
  assert grants.athletes_of(twice, "me") == [Person("ana", "Ana")]
}

pub fn the_grants_an_athlete_gave_are_sorted_by_coach_name_test() {
  let given = grants.given_by(all(), "me")
  assert list_ids(given) == ["g3", "g4"]
  assert list_ids(grants.given_by(all(), "ana")) == ["g1"]
  assert list_ids(grants.given_by(all(), "carl")) == []
}

fn list_ids(gs: List(grants.Grant)) -> List(String) {
  case gs {
    [] -> []
    [g, ..rest] -> [g.id, ..list_ids(rest)]
  }
}

pub fn a_user_is_called_by_the_name_the_grants_carry_test() {
  assert grants.name_of(all(), "ana") == Some("Ana")
  assert grants.name_of(all(), "carl") == Some("Carl")
  assert grants.name_of(all(), "me") == Some("Me Athlete")
  assert grants.name_of(all(), "stranger") == None
}

pub fn an_empty_name_is_not_a_name_test() {
  assert grants.name_of([grant("g", "x", "y", "", "")], "x") == None
}

pub fn has_grant_checks_the_pair_test() {
  assert grants.has_grant(all(), "me", "carl")
  assert !grants.has_grant(all(), "carl", "me")
  assert !grants.has_grant(all(), "me", "eve")
}
