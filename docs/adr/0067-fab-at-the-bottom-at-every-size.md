# 0067. The FAB at the bottom right of the content at every size

- Status: Superseded by [0068](0068-main-action-in-the-app-bar.md)
- Date: 2026-10-09
- Deciders: owner (did not want the FAB in the navigation rail; chose this of the proposed options)

## Context

[ADR 0060](0060-window-size-classes-and-list-detail.md) put the floating action button at the top of the navigation
rail from the medium window class, as an icon without its label. That is one of Material Design 3's placements, but
it moved the screen's main action away from the content it acts on and hid its label.

## Options considered

1. **Bottom right of the content at every size (chosen)** — M3's default place for a FAB at any window size.
2. **A filled button in the app bar from medium** — reads like a desktop app, but two placements, and a busy app bar
   on a plan's page.
3. **A button at the top of the content from medium** — next to what it acts on, but it scrolls away; two placements.
4. **An Expressive floating toolbar** — more than one action per screen needs.

## Decision

The extended FAB (icon and label) floats at the bottom right at every size: above the navigation bar on a phone, and
lined up with the right edge of the content column on wider screens (`--content-max`, `--rail-width`), so it stays
near what it acts on. The rail no longer holds it, the content keeps room under its last item, and a snackbar shows
above it.

## Consequences

- One placement to know and to test; the label is always shown.
- The content column's widest (`--content-max`, 48rem, 80rem on a plan's calendar) is one variable, which the app bar
  and the FAB use too.
