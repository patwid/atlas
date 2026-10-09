# 0069. One section heading, whole-row links and an empty state on every list

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to go ahead with the layout review's suggested order); agent (the details below)

## Context

A review of the app's layout found the same patterns drawn differently from screen to screen:

- **Section headings**: the plan list had M3 list subheaders ([ADR 0055](0055-material-review-quick-fixes.md)), but
  Today, an athlete's page and the training zones used `h3`s with no style of their own (browser defaults), skipping
  `h2` under the app bar's `h1`; "Athletes you coach" was an unstyled `h2`, and Today repeated its title as a date
  heading and a "Today" heading.
- **Rows that open a page**: in the plan, athlete and coached-athlete lists only the headline text was the link, so a
  tap on a row's chips or supporting text did nothing, unlike the Settings list ([ADR 0049](0049-settings-list-and-banners.md)).
- **Empty states** ([ADR 0050](0050-chips-empty-states-button-icons.md)): the plan list, activities and coaches had
  them; a plan's calendar, schedule and sharing tabs, a plan not on the device and an athlete one does not coach had
  a line of muted text. The coaches' full-size empty state pointed "below" to a field it pushed off a phone's screen.

## Decision

- **`layout.subheader`** draws every section heading as an `h2` in M3's list-subheader style (class `subheader`,
  the former `.plans h2`), lined up with the list items' text: the plan list, Today's groups (the first one is
  "Today · <date>", the separate date heading is gone), an athlete's page, the coaches page ("Your coaches", "Athletes
  you coach") and the training zones' three parts. An empty state's headline is an `h2` too.
- **`layout.row_link`** is a list item's headline link whose hit area (`::after`, `inset: 0`) covers the whole item,
  with the state layer and the segmented list's shape change on hover, like the Settings list. The plan, athlete and
  coached-athlete lists use it.
- **Every list says when it is empty with `empty.view`**, with copy that names the button to use ("Use Start this plan
  to begin.", "Add the first one with Add workout."), and a page that is not there offers the way back ("All plans",
  "All athletes"). **`empty.compact`**, a smaller one, is for a list with a form under it (coaches, sharing).

## Consequences

- One place each for the heading, the row link and the empty state; a new screen gets them by using the helpers.
- A row drawn with `row_link` cannot hold its own buttons or links: the link's hit area would cover them. Rows with
  actions (activities, shares, schedules) keep their menus and do not use it.
