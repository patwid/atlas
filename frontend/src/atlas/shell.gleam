//// The page frame: header, offline notice, navigation and the page placeholders.
//// The pages are empty states until the data layer (ADR 0004) is in place.

import atlas/route.{type Route}
import gleam/list
import lustre/attribute.{class}
import lustre/element.{type Element}
import lustre/element/html

/// `coaching` adds the Athletes tab, for people whom someone has given access to (ADR 0031).
pub fn view(
  route: Route,
  online: Bool,
  coaching: Bool,
  page: Element(msg),
) -> Element(msg) {
  html.div([class("shell")], [
    html.header([class("bar")], [
      html.h1([], [html.text(route.title(route))]),
      case online {
        True -> element.none()
        False ->
          html.span([class("pill"), attribute.role("status")], [
            html.text("Offline"),
          ])
      },
    ]),
    html.main([attribute.id("main")], [page]),
    nav(route, coaching),
  ])
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
  html.nav([class("tabs"), attribute.aria_label("Main")], {
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
        [html.text(label)],
      )
    })
  })
}

/// Pages under the same tab share a section, so a plan keeps "Plans" highlighted.
fn section(r: Route) -> Route {
  case r {
    route.Plan(_) -> route.Plans
    route.Athlete(_) -> route.Athletes
    other -> other
  }
}

pub fn empty(title: String, hint: String) -> Element(msg) {
  html.section([class("empty")], [
    html.h2([], [html.text(title)]),
    html.p([], [html.text(hint)]),
  ])
}
