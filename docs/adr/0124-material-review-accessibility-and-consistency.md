# 0124. Material review, second round: bugs, consistency and accessibility

- Status: Accepted
- Date: 2026-10-12
- Deciders: owner (asked to fix the review's items); agent (the review and the details below)

## Context

A second review of the whole app against Material Design 3 (M3) and M3 Expressive, made on the running app in
Chromium at phone and desktop widths in both schemes and on `app.css` and the `ui` modules, found three bugs, a few
places where the app strayed from M3's patterns, and accessibility gaps. The first round was
[ADR 0055](0055-material-review-quick-fixes.md) and [0062](0062-material-review-remaining-items.md).

## Decision

**Bugs**

- `.list a` no longer styles links drawn as buttons: the "Go to activities" action in Home's activity dialog, inside a
  list, had lost its text-button look.
- A basic or confirmation dialog closes on a click outside its box only, not on a click on its own padding, whose
  target is the dialog too (`clickedOutside` in `atlas/ui/interaction`).
- The small app bar's title stays on one line and ends in an ellipsis, also when the medium bar collapses into it.

**Consistency**

- Home's state of a workout is an icon and a word in the colour of its kind, not a chip-shaped label: in M3 a chip is
  something to press (changes [ADR 0048](0048-material-navigation-progress-status.md)). A rest day shows no state, as
  its kind's chip already says it. A day's date and plan go into the item's supporting line, with what is planned.
- A list item's headline is body-large at 400 everywhere: links, buttons and plain text (`strong`). It no longer
  underlines on hover; the state layer shows it.
- Settings' account row has the name as its headline and the e-mail address as its supporting text. Training zones'
  heart is the outlined icon, as the other rows' icons are.
- An interval part's zone has a line of its own and its distance and time share the next, so no label is cut short;
  their help is short ("90 or 1:30 (m:ss)"), as it comes back in every part.
- The calendar's small text is body-small (12/16) instead of 13px; other small text gets M3's line height and
  tracking.
- The Strava page on a server without Strava shows an empty state, like other pages with nothing to show.
- An athlete's page opens with two filled cards: this week's workouts done, with a meter, and the workouts missed in
  the last six weeks, instead of a bold sentence.

**Accessibility**

- A snackbar with an action (Undo) stays 10 seconds, M3's longest, and does not run out while it is pointed at or has
  the focus (`timer.after_unheld`; WCAG 2.2.1).
- Snackbars and loading indicators carry their text in `data-announce`; one live region stays in the page, outside the
  app's root, and each new message is put into it. A live region added together with its text is often not read.
- Menu items show the focus ring, have a pressed state and ripple; Tab closes an open menu.
- Icon buttons have M3's 48px touch target around their 40px circle: their `::before` reaches 4px past it, so their
  state layer is their background and their ripple grows from the centre. Chips get 48px through their label's
  padding, taken back by margins. The wide calendar's add button is 40px on touch screens.
- Text and icons reach WCAG contrast: days before a plan's start and empty days are quieter through their colours, not
  opacity; the wide calendar's faint add buttons are at 60%; "View on Strava" is bold and underlined in the text
  colour on light surfaces, where Strava's orange is about 3.2:1, and orange in the dark scheme (Strava's rules allow
  bold or underlined in place of the orange; changes [ADR 0027](0027-strava-screen.md)).
- Confirmation dialogs are `alertdialog`s with an `h2` headline and `aria-describedby` on their sentence; the date
  picker's `aria-selected` is on the grid cell; a week's goal meter grows its maximum past 100% with its value.

**Polish**

- An invalid field keeps an error colour on hover; disabled icon buttons are drawn as disabled; the FAB rises to
  level 4 on hover (`--md-sys-elevation-4`); the ripple starts at the pressed opacity and a rippling element keeps only
  its hover layer under it, so the two no longer add up to 20%.

## Consequences

- Not done: dark colours for the installed app's splash screen. The web app manifest has one `theme_color` and
  `background_color` and no standard way to give dark ones, so the splash stays light; the pages' own `theme-color`
  already follows the scheme.
- The live region is the one node the interaction module adds; it sits outside `#app`, so Lustre never sees it.
- Two items of the review were left to the owner and not changed: wide screens still show one content column, and form
  dialogs on wider screens keep a filled Save ([ADR 0085](0085-form-dialog-spacing-pairs-and-buttons.md)).
