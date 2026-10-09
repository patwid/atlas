# 0074. Activity rows without the usual, a Duration field, and the Strava page's problems and actions

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's other items); agent (the details below)

## Context

From the layout review:

- **Activities**: almost every row had the chip "Added by hand" ([ADR 0050](0050-chips-empty-states-button-icons.md)),
  an unnamed activity showed its sport as its title and again on its date line, and its figures were in the muted
  supporting colour like the date. The form's "Time" sat beside "Start time", and that one of Distance and Time is
  needed was said only after Save.
- **Strava**: an unavailable status was a muted line with no way to try again, a failed action was red text below
  Strava's attribution, and "Import the last 30 days again" and "Disconnect", which removes data, were the same
  outlined button side by side.

## Decision

- An activity entered by hand has no source chip; Strava, Garmin and file imports keep theirs. The date line leaves
  out the sport when it is the title. The figures are in `on-surface`.
- The activity and workout forms' "Time" is "Duration" (also in the week dialog), and Distance's supporting text is
  "A distance, a duration or both".
- On the Strava page, problems are error banners ([ADR 0049](0049-settings-list-and-banners.md)) at the top: a status
  that could not be read has Try again, a failed action has Dismiss. Importing again is a tonal button; Disconnect is a
  text button at the end of the row, still behind its confirmation.

## Consequences

- The usual case says nothing; what is unusual (synced, not yet uploaded) stands out.
