//// The page frame: header, offline banner, navigation and the page placeholders.
//// The pages are empty states until the data layer (ADR 0004) is in place.

import atlas/route.{type Route}
import atlas/ui/banner
import atlas/ui/empty as ui_empty
import atlas/ui/icon
import gleam/list
import gleam/option.{None}
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// `coaching` adds the Athletes tab, for people whom someone has given access to (ADR 0031). `syncing` shows a
/// progress bar under the app bar while a sync runs (ADR 0048).
pub fn view(
  route: Route,
  online: Bool,
  coaching: Bool,
  syncing: Bool,
  page: Element(msg),
) -> Element(msg) {
  html.div([class("shell")], [
    html.header([class("bar")], [
      html.div([class("bar-content")], [
        up(route),
        html.h1([], [html.text(route.title(route))]),
      ]),
      case syncing {
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
    ]),
    html.main([attribute.id("main")], [
      case online {
        True -> element.none()
        // A banner rather than a chip in the bar (ADR 0049): it says what being offline means.
        False ->
          banner.view(
            [class("banner-offline"), attribute.role("status")],
            icon.CloudOff,
            [
              html.strong([], [html.text("Offline. ")]),
              html.text(
                "Your changes are kept on this device and synced when you are back online.",
              ),
            ],
            [],
          )
      },
      page,
    ]),
    nav(route, coaching),
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
      class("md-icon-button"),
      attribute.href(route.to_path(target)),
      attribute.aria_label(label),
      attribute.title(label),
    ],
    [icon.view(icon.ArrowBack)],
  )
}

fn nav(current: Route, coaching: Bool) -> Element(msg) {
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
            html.span([class("nav-indicator")], [icon.view(tab_icon(target))]),
            html.text(label),
          ],
        )
      })
    }),
  ])
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
