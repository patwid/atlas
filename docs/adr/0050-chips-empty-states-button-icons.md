# 0050. Badges with icons, empty states and icons in buttons

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for the remaining Material Design 3 changes); agent (the details below)

## Context

Three smaller gaps to Material Design 3 (M3) remained after [ADR 0049](0049-settings-list-and-banners.md):

- Badges ("Public", "Not synced yet", an activity's source, a workout's kind) were all the same plain label, so a
  state and a category looked alike.
- An empty list or a missing page was a grey sentence, sometimes with an inline link.
- Buttons were text only; M3 puts a leading icon on buttons whose action has a common icon.

## Decision

- **Badges** (`atlas/ui/badge`): `badge` stays for a category (a workout's kind); `with_icon` adds a leading icon
  for a state or origin: "Public" (globe), "Not synced yet" (cloud upload), and an activity's source (edit note for
  "Added by hand", link for Strava and Garmin; none for a file).
- **Empty states** (`atlas/ui/empty`): an icon in a tonal circle, a headline, a line of help and an optional action
  rendered as a tonal button link. Used for no plans, no activities ("Connect Strava"), not following a plan
  ("Go to plans"), no athletes, no coaches, and "Page not found". The wording tests rely on is kept as the
  headline.
- **Icons in buttons**: Edit (pencil), Delete (bin) and Copy to my plans (copy) carry a leading icon; the label
  still names the action, and the icon is hidden from screen readers.

## Consequences

- States and categories are told apart at a glance; empty screens say what to do next.
- Adding an icon to another button is one `icon.view` before its label; new icons are added to `atlas/ui/icon`
  from the same Google package.
