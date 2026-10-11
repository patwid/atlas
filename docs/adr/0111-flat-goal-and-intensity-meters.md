# 0111. Flat goal and intensity meters instead of the wave

- Status: Accepted
- Date: 2026-10-11
- Deciders: owner (asked for a straight progress bar in the plan view); agent (the details below)

## Context

[ADR 0053](0053-material-3-expressive.md) made the active indicator of the goal and intensity meters M3 Expressive's
wave. Expressive keeps the flat linear indicator as a standard variant and shows the wave for something that is
going on, like a download. These meters are readings, not activity: a week's distance against its goal and its
intensity. The wave also makes the filled length harder to judge, especially in the small 3rem meter of a week's row.

## Options considered

1. **Keep the wave** — consistent with 0053, but harder to read for no gain.
2. **A flat indicator (chosen)** — M3's determinate linear progress as in [ADR 0051](0051-material-slider-progress-motion.md).

## Decision

- The meters' active indicator is a flat bar, 4px high with full rounding, followed by the gap, the track and the
  stop dot as before. The over-goal color stays.
- This replaces only the "Wavy progress" part of 0053; the rest of 0053 stands.

## Consequences

- No progress indicator in the app is wavy any more; the sync bar under the app bar was already flat (0095).
- The meter keeps its 10px height, so the layout around it does not move.
