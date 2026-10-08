# 0047. Use more Material Design 3 components: snackbar, FAB, segmented buttons, chips, lists, tonal button

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (agreed to the agent's proposal to adopt these); agent (the details below)

## Context

After [ADR 0044](0044-material-design-3-styling.md)-[0046](0046-material-button-names.md) the app looks like
Material Design 3 (M3), but several screens still use plain elements where M3 has a component for the job:

- Status messages ("Copied to your plans", Strava's info, "Saved." for zones) were paragraphs placed wherever the
  page had room, each in its own way.
- The main action of the plans and activities lists ("New plan", "Add activity") was a filled button in the header.
- Small fixed choices (plan visibility, workout kind, sport) were dropdowns that hid their options.
- Lists of plans, coaches, shares and athletes were separate outlined cards.

## Options considered

1. **Leave them as they are** — no work, but they don't match the rest of the M3 look.
2. **Hand-write these M3 components in the existing `ui` modules (chosen)** — same approach as ADR 0044: native
   elements, `app.css`, no library.
3. **Also date pickers, floating labels and bottom sheets** — much more hand-written behaviour for little gain over
   the native controls; left out.

## Decision

- **Icons** (`atlas/ui/icon`): Material Icons as inline SVG paths, shared by the navigation, buttons and chips.
- **Snackbar** (`atlas/ui/snackbar`): a message about something the app just did, fixed at the bottom of the screen
  (above the navigation bar and FAB), with at most one action and a close button; `role="status"`. Used for a
  plan copy (with "Open your copy"; closing it brings the Copy button back, replacing "Copy again"), Strava's info
  messages and saved zones. It does not hide by itself: the page clears it on close or on the next change, so a
  screen reader user is not raced by a timer. Errors stay next to what they are about.
- **Extended FAB** (`button.fab`): "New plan" and "Add activity", fixed bottom right. The form still opens at the
  top of the page, so the click moves the focus to its first field (`focus.soon`), which also scrolls it into view.
  Only list screens get one: a plan's own screen has several equal actions.
- **Segmented buttons and filter chips** (`atlas/ui/choice`): a group of native radio buttons styled as M3 draws
  them, so keyboard and screen readers treat it as one choice. Segmented for plan visibility ("Only me" /
  "Everyone", with the longer explanation as supporting text below); chips for workout kind and sport, which have
  too many options for a segmented row. Week, day and athlete stay selects (long or data-driven lists).
- **Lists** (`layout.list`, class `list`): items in one container with dividers instead of separate cards; the
  link is the headline and paragraphs are supporting text. Today's "Which activity was it?" choices use it too.
- **Tonal button** (`button.tonal`): "Copy to my plans", "Try again", "This one" and the "Work out zones from …"
  helpers, which move things forward but are not the screen's main action.

## Consequences

- One way to show a status message, one place for a list screen's main action, and visible choices instead of
  dropdowns for kind, sport and visibility.
- The whole-app tests pick a choice by clicking its radio button (`pick` in `test-js/support.mjs`) instead of
  setting a select's value.
- The fixed FAB and snackbar must keep clear of the navigation bar: `--nav-bar-height` in `app.css` holds its height
  (0 when the rail is used on wide screens).
