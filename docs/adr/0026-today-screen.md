# 0026. The Today screen and stored matches

- Status: Accepted
- Date: 2026-10-06
- Deciders: agent (product scope: following a plan and seeing what has been done)

## Context

The pieces for a daily view exist: assignments put workouts on dates ([0023](0023-assignments.md)), activities arrive by hand
([0025](0025-manual-activities.md)) or from Strava ([0012](0012-strava-integration-hooks.md)), and the matching rules ([0015](0015-domain-core.md))
can pair them. What was open is what the screen shows, and what is stored when the user confirms or corrects a pairing.

## Decision

- **The screen** shows the workouts of every plan the user follows within seven days of today: Today, Coming up and
  Last 7 days, each workout with its plan, kind, planned distance and time, and a status: *To do*, *Missed* (past, nothing linked),
  *Rest day*, *Looks done* (a suggested activity) or *Done* (a confirmed one). It is built by a pure module (`today`) from what the
  other screens already read; nothing new is fetched.
- **Suggestions are never stored.** The matching rules run every time the screen is drawn, so a suggestion follows the
  data (a new activity, a changed plan) and there is nothing to keep consistent between devices. A coach can compute the same view
  from what they may read (0009), so stored matches are not needed to show progress.
- **A stored match records a decision by the user**: "Yes, that is it" on a suggestion, "This one" from a list of that day's activities,
  or the same on a missed workout. A stored match always wins over a suggestion, and activities and workouts it uses are not suggested again.
  "Unlink" removes it; the suggestion then returns. There is no way to say "this suggestion is wrong" except to link another activity.
- **One row per activity.** `matches.activity` is unique, and a removed match keeps its row (soft delete, 0009). So linking an activity
  whose match was removed *changes that row* (undeleting it and pointing it at the new workout) instead of creating one, and linking an
  activity that is linked elsewhere moves its row. A workout that already has a different activity linked has that link removed first.
  This needed one rule change (migration `1760000200_matches_relink.js`): an update may now change `assignment`, as long as the new
  assignment is the user's own. Activity and owner stay fixed.
- **Candidates for a manual link** are the user's own activities on the same local day that no other stored match uses, those whose sport fits
  the workout first. Any sport can be chosen: the user knows best.
- **Days follow the UTC offset that applied at each activity** (0015 addendum), so a run just after a daylight-saving change counts on the right day.
- **Edits right after a save use the engine's own newest `updated`** for the record when it is newer than the screen's. Screens read the
  device database a moment after it changes; an edit in that moment (unlink, then link again at once) would otherwise be based on an older
  value and be refused as a conflict, silently losing the user's change. The engine remembers the newest value from acknowledged saves and pulls.

## Consequences

- Progress is only "stored" when the user confirms. Anything that needs a durable record of completion (a coach's report, a training log
  export) must compute suggestions the same way or ask the athlete to confirm.
- Stored matches whose activity or workout no longer exists, or that were made by someone else, are ignored. If two devices linked different
  activities to the same workout, the newer row wins.
- A workout done twice in a day, or two workouts of the same kind on one day, are paired by closeness to the planned size; the user can correct it.
- The whole-app test runs the screen against a real PocketBase and was repeated under four time zones: missed, suggested and rest-day workouts; confirm;
  unlink; re-link reusing the same row; and linking yesterday's run to a missed workout by hand.
