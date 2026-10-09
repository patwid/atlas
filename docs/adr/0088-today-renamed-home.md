# 0088. The Today screen is called Home

- Status: Accepted
- Date: 2026-10-09
- Deciders: owner (asked to rename Today to Home); agent (the details below)

## Context

The first tab, at `/`, was called Today ([ADR 0026](0026-today-screen.md)). It shows more than today, though: the
week ahead and the last seven days ([ADR 0082](0082-today-newest-first.md)). Its own group for the day is also headed
"Today", so the tab and that heading shared one name.

## Decision

The screen and its tab are called Home, with Material's `home` icon. It stays at `/` and shows the same groups; the
group for the day is still headed "Today · <date>". In the code the route is `route.Home` and the screen is
`home_page`. The pure module that works out the workouts around today keeps its name, `today`.

## Consequences

The tab reads as the app's starting point. Older ADRs still say Today for this screen; they mean Home.
