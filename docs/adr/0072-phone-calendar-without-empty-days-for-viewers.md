# 0072. The phone calendar leaves out empty days for those who cannot edit the plan

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's suggested order); agent (the details below)

## Context

Below the expanded window class the plan calendar stacks a week's seven days
([ADR 0062](0062-material-review-remaining-items.md)), so a 12-week plan is 84 day rows. For the owner an empty day
holds the button that adds a workout to it; for anyone else (a shared or public plan, a coach's view) it holds only
its name.

## Decision

On a phone and medium window, a day with neither a workout nor the add button is not drawn (CSS, `display: none`):
someone who cannot edit the plan sees each week's label followed by its workouts, each still named by its day. From
the expanded window class the days are columns and every day keeps its cell.

## Consequences

- A plan read on a phone is about as long as its number of workouts instead of seven rows a week.
- A rest week without workouts shows only its label. The owner's calendar is unchanged.
