//// The PocketBase collections the client keeps in sync (ADR 0009 and 0004).

pub type Collection {
  CoachGrants
  Plans
  PlanShares
  Workouts
  Assignments
  Activities
  Matches
}

pub const all = [
  CoachGrants,
  Plans,
  PlanShares,
  Workouts,
  Assignments,
  Activities,
  Matches,
]

pub fn to_string(collection: Collection) -> String {
  case collection {
    CoachGrants -> "coach_grants"
    Plans -> "plans"
    PlanShares -> "plan_shares"
    Workouts -> "workouts"
    Assignments -> "assignments"
    Activities -> "activities"
    Matches -> "matches"
  }
}

pub fn from_string(text: String) -> Result(Collection, Nil) {
  case text {
    "coach_grants" -> Ok(CoachGrants)
    "plans" -> Ok(Plans)
    "plan_shares" -> Ok(PlanShares)
    "workouts" -> Ok(Workouts)
    "assignments" -> Ok(Assignments)
    "activities" -> Ok(Activities)
    "matches" -> Ok(Matches)
    _ -> Error(Nil)
  }
}
