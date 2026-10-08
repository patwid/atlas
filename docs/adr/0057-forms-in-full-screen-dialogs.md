# 0057. Create and edit forms in full-screen dialogs

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked to go ahead with the Material review's next steps); agent (the details below)

## Context

Create and edit forms opened inside the page: "New plan" and "Add activity" put the form at the top of the list,
far from the floating action button that opened it (the app moved the focus there to make up for it); editing an
activity or a schedule entry replaced its list item; adding or editing a workout used the calendar's sidebar,
which on a phone is a bottom sheet of at most 65% of the screen ([ADR 0052](0052-calendar-bottom-sheet.md)).
Material Design 3 (M3) uses a full-screen dialog for creating and editing on a phone, and a basic dialog on larger
screens.

## Options considered

1. **Pages of their own** (`/plans/new`, `/activities/:id/edit`) — real addresses, but more routes and the page
   behind is gone.
2. **Full-screen dialogs (chosen)** — what M3 prescribes; the list or calendar stays behind.

## Decision

- `atlas/ui/form_dialog` draws a native modal `<dialog>`: a top bar with Close (✕, "Cancel"), the title and the
  submit button (outside the form, tied to it with `form=`), then the form. Under 600px it fills the screen; from
  600px it is a dialog of at most 560px with M3's extra-large corners. A click outside does not close it, so typing
  is never lost by a stray tap; Escape and Close do, and send the page's cancel message.
- It is declarative: the page says `open` from its own mode, and `atlas/ui/interaction` calls `showModal()` or
  `close()` whenever a dialog's `data-open` changes (a `MutationObserver`). No page needs an effect to open or close
  it, and the dialog cannot drift from the page's mode.
- Plans (new, edit), activities (new, edit), workouts (new, edit) and the schedule (start, change date) use it; the
  forms lose their own Save and Cancel buttons. The calendar's sidebar and bottom sheet show only details.
- The plan's settings stay in the sidebar: a few numbers edited beside the calendar they change.

## Consequences

- The date and time pickers ([ADR 0054](0054-material-date-and-time-pickers.md)) open over the form dialog.
- Tests find the open form dialog by `.form-dialog[open]`; the dialog's syncing is tested in `interaction.test.mjs`.
