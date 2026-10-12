//// The PocketBase collections the client keeps in sync (ADR 0009 and 0004).

pub type Collection {
  CoachGrants
  Plans
  Workouts
  Assignments
  Activities
  Matches
  AthleteSettings
  Goals
}

pub const all = [
  CoachGrants,
  Plans,
  Workouts,
  Assignments,
  Activities,
  Matches,
  AthleteSettings,
  Goals,
]

pub fn to_string(collection: Collection) -> String {
  case collection {
    CoachGrants -> "coach_grants"
    Plans -> "plans"
    Workouts -> "workouts"
    Assignments -> "assignments"
    Activities -> "activities"
    Matches -> "matches"
    AthleteSettings -> "athlete_settings"
    Goals -> "goals"
  }
}

pub fn from_string(text: String) -> Result(Collection, Nil) {
  case text {
    "coach_grants" -> Ok(CoachGrants)
    "plans" -> Ok(Plans)
    "workouts" -> Ok(Workouts)
    "assignments" -> Ok(Assignments)
    "activities" -> Ok(Activities)
    "matches" -> Ok(Matches)
    "athlete_settings" -> Ok(AthleteSettings)
    "goals" -> Ok(Goals)
    _ -> Error(Nil)
  }
}

/// A short name for messages: "plan", "workout", ...
pub fn label(collection: Collection) -> String {
  case collection {
    CoachGrants -> "coach grant"
    Plans -> "plan"
    Workouts -> "workout"
    Assignments -> "assignment"
    Activities -> "activity"
    Matches -> "match"
    AthleteSettings -> "setting"
    Goals -> "goal"
  }
}
