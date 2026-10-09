//// The page frame: the app bar, the navigation and the page placeholders.
//// The pages are empty states until the data layer (ADR 0004) is in place.

import atlas/route.{type Route}
import atlas/ui/empty as ui_empty
import atlas/ui/icon
import gleam/int
import gleam/list
import gleam/option.{None}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event

/// What the frame shows around a page.
pub type Frame(msg) {
  Frame(
    route: Route,
    /// The app bar's title: the page's, or the name of the plan or athlete on show (ADR 0055).
    title: String,
    online: Bool,
    /// Adds the Athletes tab, for people whom someone has given access to (ADR 0031).
    coaching: Bool,
    /// Shows a progress bar under the app bar while a sync runs (ADR 0048).
    syncing: Bool,
    /// Sync problems waiting for the user: a badge on the Settings tab (ADR 0055).
    problems: Int,
    /// Pressing the app bar's offline icon, which explains being offline (ADR 0055).
    on_offline_info: msg,
    /// The page's own actions at the end of the app bar, such as a plan's Edit and menu (ADR 0058).
    actions: Element(msg),
    /// The screen's main action as an app bar button, shown from the medium window class (a FAB on a phone,
    /// ADR 0068).
    main_action: Element(msg),
  )
}

pub fn view(frame: Frame(msg), page: Element(msg)) -> Element(msg) {
  html.div([class("shell")], [
    // A plan's or an athlete's page has M3's medium app bar (ADR 0062): its name on a line of its own, in a larger
    // size, until the page scrolls and the bar becomes the small one.
    html.header(
      [
        class("bar"),
        attribute.classes([
          #("bar-medium", case frame.route {
            route.Plan(_) | route.Athlete(_) -> True
            _ -> False
          }),
        ]),
      ],
      [
        html.div([class("bar-content")], [
          up(frame.route),
          html.h1([], [html.text(frame.title)]),
          frame.main_action,
          frame.actions,
          case frame.online {
            True -> element.none()
            // An icon rather than a banner (ADR 0055): being offline is ordinary for this app, so it is shown
            // quietly, and a snackbar says what it means when it happens or when the icon is pressed.
            False ->
              html.button(
                [
                  attribute.type_("button"),
                  class("md-icon-button offline-indicator"),
                  attribute.aria_label("Offline. What does this mean?"),
                  attribute.title("Offline"),
                  event.on_click(frame.on_offline_info),
                ],
                [icon.view(icon.CloudOff)],
              )
          },
        ]),
        case frame.syncing {
          True ->
            html.div(
              [
                class("md-linear-progress"),
                attribute.role("progressbar"),
                attribute.aria_label("Syncing"),
              ],
              [],
            )
          False -> element.none()
        },
      ],
    ),
    html.main([attribute.id("main")], [
      // Keyed by the address, so a new page is a new element and fades in (ADR 0051).
      keyed.div([class("page")], [#(route.to_path(frame.route), page)]),
    ]),
    nav(frame.route, frame.coaching, frame.problems),
  ])
}

/// The app bar's back button on a page inside a tab (ADR 0048): it goes up to that tab's list.
fn up(current: Route) -> Element(msg) {
  case current {
    route.Plan(_) -> up_link(route.Plans, "All plans")
    route.Athlete(_) -> up_link(route.Athletes, "All athletes")
    route.SettingsPage(_) -> up_link(route.Settings, "All settings")
    _ -> element.none()
  }
}

fn up_link(target: Route, label: String) -> Element(msg) {
  html.a(
    [
      class("md-icon-button up-link"),
      attribute.href(route.to_path(target)),
      attribute.aria_label(label),
      attribute.title(label),
    ],
    [icon.view(icon.ArrowBack)],
  )
}

fn nav(current: Route, coaching: Bool, problems: Int) -> Element(msg) {
  let items = case coaching {
    True -> [
      #(route.Today, "Today"),
      #(route.Plans, "Plans"),
      #(route.Activities, "Activities"),
      #(route.Athletes, "Athletes"),
      #(route.Settings, "Settings"),
    ]
    False -> [
      #(route.Today, "Today"),
      #(route.Plans, "Plans"),
      #(route.Activities, "Activities"),
      #(route.Settings, "Settings"),
    ]
  }
  html.nav([class("tabs"), attribute.aria_label("Main")], [
    html.div([class("tabs-content")], {
      list.map(items, fn(item) {
        let #(target, label) = item
        let active = section(target) == section(current)
        html.a(
          [
            attribute.href(route.to_path(target)),
            ..case active {
              True -> [attribute.attribute("aria-current", "page")]
              False -> []
            }
          ],
          [
            html.span([class("nav-indicator")], [
              // Material 3: the selected destination's icon is filled, the others outlined.
              case active {
                True -> icon.filled(tab_icon(target))
                False -> icon.view(tab_icon(target))
              },
              badge(target, problems),
            ]),
            html.text(label),
            badge_text(target, problems),
          ],
        )
      })
    }),
  ])
}

/// A Material 3 badge with the number of sync problems on the Settings tab, so they are seen from anywhere. The
/// number is drawn only; `badge_text` reads it out after the tab's name (an `aria-label` on a `span` is not read).
fn badge(target: Route, problems: Int) -> Element(msg) {
  case target, problems {
    route.Settings, n if n > 0 ->
      html.span([class("nav-badge"), attribute.aria_hidden(True)], [
        html.text(int.to_string(int.min(n, 99))),
      ])
    _, _ -> element.none()
  }
}

fn badge_text(target: Route, problems: Int) -> Element(msg) {
  case target, problems {
    route.Settings, 1 ->
      html.span([class("visually-hidden")], [html.text(", 1 sync problem")])
    route.Settings, n if n > 1 ->
      html.span([class("visually-hidden")], [
        html.text(", " <> int.to_string(n) <> " sync problems"),
      ])
    _, _ -> element.none()
  }
}

fn tab_icon(target: Route) -> icon.Icon {
  case target {
    route.Today -> icon.Today
    route.Plans -> icon.EventNote
    route.Activities -> icon.DirectionsRun
    route.Athletes -> icon.Group
    _ -> icon.Settings
  }
}

/// Pages under the same tab share a section, so a plan keeps "Plans" highlighted.
fn section(r: Route) -> Route {
  case r {
    route.Plan(_) -> route.Plans
    route.Athlete(_) -> route.Athletes
    route.SettingsPage(_) -> route.Settings
    other -> other
  }
}

pub fn empty(title: String, hint: String) -> Element(msg) {
  html.section([], [ui_empty.view(icon.SearchOff, title, hint, None)])
}
