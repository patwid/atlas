//// Coach grants: who may see whose training (ADR 0009). The athlete creates a grant for a coach.
//// The display names come with the grant, so they are known offline (ADR 0023).

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Grant {
  Grant(
    id: String,
    athlete_id: String,
    coach_id: String,
    athlete_name: String,
    coach_name: String,
    /// The `updated` value of the local copy: the base for edits (ADR 0011).
    updated: String,
  )
}

pub type Person {
  Person(id: String, name: String)
}

/// The athletes who granted `me` access, by name.
pub fn athletes_of(grants: List(Grant), me: String) -> List(Person) {
  grants
  |> list.filter(fn(g) { g.coach_id == me })
  |> list.map(fn(g) { Person(g.athlete_id, label(g.athlete_name)) })
  |> list.unique
  |> sort_people
}

/// The grants `me` has given to coaches, by coach name.
pub fn given_by(grants: List(Grant), me: String) -> List(Grant) {
  grants
  |> list.filter(fn(g) { g.athlete_id == me })
  |> list.sort(fn(a, b) {
    string.compare(
      string.lowercase(a.coach_name),
      string.lowercase(b.coach_name),
    )
  })
}

/// What to call a user the grants know about. `None` for strangers.
pub fn name_of(grants: List(Grant), user_id: String) -> Option(String) {
  case
    list.find(grants, fn(g) { g.athlete_id == user_id && g.athlete_name != "" })
  {
    Ok(g) -> Some(g.athlete_name)
    Error(Nil) ->
      case
        list.find(grants, fn(g) { g.coach_id == user_id && g.coach_name != "" })
      {
        Ok(g) -> Some(g.coach_name)
        Error(Nil) -> None
      }
  }
}

/// Whether the coach already has a grant from the athlete.
pub fn has_grant(
  grants: List(Grant),
  athlete_id: String,
  coach_id: String,
) -> Bool {
  list.any(grants, fn(g) {
    g.athlete_id == athlete_id && g.coach_id == coach_id
  })
}

fn label(name: String) -> String {
  case string.trim(name) {
    "" -> "Unnamed athlete"
    named -> named
  }
}

fn sort_people(people: List(Person)) -> List(Person) {
  list.sort(people, fn(a, b) {
    string.compare(string.lowercase(a.name), string.lowercase(b.name))
  })
}
