# 0107. On a phone, a day's add button at the trailing edge

- Status: Accepted
- Date: 2026-10-11
- Deciders: owner (found the phone calendar's days and add buttons off and asked for improvements); agent (the details below)

## Context

On a phone the days of a week stack ([0043](0043-plan-phases-goal-and-calendar.md), [0072](0072-phone-calendar-without-empty-days-for-viewers.md)):
a day was its name in a 3.5rem column and a body with its workouts and then the 40px add button
([0075](0075-calendar-add-button-titles-and-week-names.md)). That put the button on a line of its own under the
workouts, at the left of the body, so a day with a workout grew by a row and the button moved with the number of workouts.
The day's name sat at the top of its row while the button beside it was 40px tall, so on an empty day the two did not
line up, and a week without workouts read as a list of names with a "+" next to each.

## Options considered

1. **The add button in a column of its own at the trailing edge** of each day, with the name lined up with the first
   workout, or centred with the button on a day without workouts.
2. **No add button per day on a phone**: tapping a day would add a workout to it, with the FAB ([0068](0068-main-action-in-the-app-bar.md))
   for the rest. Fewer controls, but it goes back on 0075's button that is always there on touch screens, and a tap on a
   day would mean "add" where a tap on a workout means "open".
3. **A smaller button** under the workouts: less room taken, but still out of line and a smaller target.

## Decision

Option 1. The button is no longer inside the day's body but follows it in the day's cell. On a phone the day is a grid of
the name, the workouts and the button (only for those who can edit); the name's line height and top padding match a
workout's, and a day without workouts centres the name and the button. The wide calendar is unchanged: the button still
comes after the day's workouts in its cell.

## Consequences

- A day with workouts on a phone is no taller than its workouts, and the add buttons of a week form one column where the
  thumb reaches.
- The workouts lose the button's width (about 3rem) on a phone; titles wrap a little sooner.
