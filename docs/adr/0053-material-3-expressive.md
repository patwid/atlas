# 0053. Adopt Material 3 Expressive's shapes, motion and components where they fit

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner (asked for Material 3 Expressive); agent (the selection and details below)

## Context

Material 3 Expressive (2025) extends Material Design 3 (M3) with spring-based motion, a larger shape scale and a
shape library, emphasized type styles, and new or reworked components: connected button groups, segmented lists,
shape-morphing buttons, a loading indicator and wavy progress indicators, toolbars, FAB menus and split buttons.
The app follows M3 by hand ([ADR 0044](0044-material-design-3-styling.md)-[0052](0052-calendar-bottom-sheet.md)).

Google's `@material/web` package (M3 tokens 34.0) ships the Expressive tokens: `md.sys.motion.spring.*` (stiffness
and damping), the new corner sizes, `button-group-connected`, `list` (segmented), `loading-indicator`,
`progress-indicator-linear` (wave) and the emphasized type scale.

## Options considered

1. **Stay on baseline M3** — no work; the app keeps the 2021-2024 look.
2. **Adopt all of Expressive** — toolbars, FAB menus and split buttons have no use in Atlas yet; adding them would be
   change for its own sake.
3. **Adopt the parts that improve existing screens, from the published tokens (chosen).**

## Decision

- **Motion**: the six spring tokens (fast, default and slow; spatial and effects) become CSS `linear()` easings
  sampled from the spring equation, each with its settle time. Spatial springs move and resize (dialogs, snackbar,
  bottom sheet, shape changes); effects springs fade and recolor (page fade, selection colors).
- **Shapes**: the new corner tokens (large-increased 20px, extra-large-increased 32px, extra-extra-large 48px) and six
  shapes from the shape library (soft burst, 9-sided cookie, pentagon, sunny, 4-sided cookie, oval), drawn as
  72-point polygons so `clip-path` can morph between them. Google defines them with rounded-polygon geometry; these
  are close approximations, not the exact outlines.
- **Buttons**: the small button's 16px side space and 20px icons; buttons, FABs and icon buttons square off to the
  small corner while pressed, on the fast spatial spring.
- **Connected button group** instead of segmented buttons for plan visibility: tonal buttons 2px apart, round outer
  and small inner corners (extra-small while pressed), the selected one fully round. Selected chips take the medium
  corner (the toggle shape).
- **Segmented lists**: list items are separate filled shapes 2px apart, large corners at the list's ends and
  extra-small between items; a Settings row rounds further on hover, press and focus.
- **Emphasized type**: the app bar title, dialog headlines and empty-state headlines use the emphasized weights.
- **Loading indicator**: "Checking…" and "Copying…" show the 38px morphing, turning shape instead of a spinner
  (`progress.loading`, was `progress.circular`).
- **Wavy progress**: the goal and intensity meters' active indicator is the wave (3px amplitude, 40px wavelength,
  4px thick), with the flat track and stop dot.
- **Empty states**: the icon sits in the 9-sided cookie shape instead of a circle.
- Not adopted: toolbars, FAB menus, split buttons, button sizes other than small, and the Expressive color scheme
  variant (the colors stay M3's baseline, [ADR 0045](0045-material-baseline-colors.md)).

## Consequences

- `test-js/css.test.mjs` parses `app.css` and checks that every custom property it uses is defined, so a typo in
  the hand-written CSS fails the tests instead of silently breaking a page. `css-tree` (already installed through
  jsdom) becomes a direct test dependency.
- `linear()` easings need Chrome 113, Firefox 112 or Safari 17.2; older browsers ignore those transitions and
  change instantly.
- The springs and shapes are copied values; regenerating them is a small script over the token values.
