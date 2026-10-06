//// A recorded session, as far as the domain logic needs it.

pub type Source {
  Strava
  Fit
  Manual
  Garmin
}

pub type Sport {
  Run
  TrailRun
  Walk
  Hike
  Ride
  Swim
  Strength
  Other
}

pub type Activity {
  Activity(
    id: String,
    source: Source,
    /// UTC timestamp as stored by PocketBase, for example `2026-10-01 07:00:00.000Z`.
    started_at: String,
    sport: Sport,
    distance_m: Float,
    moving_time_s: Int,
  )
}

pub fn sport_from_string(text: String) -> Result(Sport, Nil) {
  case text {
    "run" -> Ok(Run)
    "trail_run" -> Ok(TrailRun)
    "walk" -> Ok(Walk)
    "hike" -> Ok(Hike)
    "ride" -> Ok(Ride)
    "swim" -> Ok(Swim)
    "strength" -> Ok(Strength)
    "other" -> Ok(Other)
    _ -> Error(Nil)
  }
}

pub fn sport_to_string(sport: Sport) -> String {
  case sport {
    Run -> "run"
    TrailRun -> "trail_run"
    Walk -> "walk"
    Hike -> "hike"
    Ride -> "ride"
    Swim -> "swim"
    Strength -> "strength"
    Other -> "other"
  }
}

pub fn source_from_string(text: String) -> Result(Source, Nil) {
  case text {
    "strava" -> Ok(Strava)
    "fit" -> Ok(Fit)
    "manual" -> Ok(Manual)
    "garmin" -> Ok(Garmin)
    _ -> Error(Nil)
  }
}

pub fn source_to_string(source: Source) -> String {
  case source {
    Strava -> "strava"
    Fit -> "fit"
    Manual -> "manual"
    Garmin -> "garmin"
  }
}
