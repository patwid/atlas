import atlas/route
import atlas/shell
import gleam/string
import lustre/element
import lustre/element/html

fn frame(r: route.Route) -> shell.Frame(Nil) {
  shell.Frame(
    route: r,
    title: route.title(r),
    online: True,
    coaching: False,
    syncing: False,
    problems: 0,
    on_offline_info: Nil,
    actions: element.none(),
    main_action: element.none(),
  )
}

fn html_of(f: shell.Frame(Nil)) -> String {
  element.to_string(shell.view(f, html.text("")))
}

pub fn a_page_inside_a_tab_has_a_back_button_to_its_list_test() {
  let plan = html_of(frame(route.Plan("p1")))
  assert string.contains(plan, "aria-label=\"All plans\"")
  assert string.contains(plan, "href=\"/plans\"")
  assert string.contains(
    html_of(frame(route.Athlete("a1"))),
    "aria-label=\"All athletes\"",
  )
}

pub fn a_settings_page_goes_back_to_all_settings_test() {
  let zones = html_of(frame(route.SettingsPage(route.Zones)))
  assert string.contains(zones, "aria-label=\"All settings\"")
  assert string.contains(zones, "Training zones")
}

pub fn a_tab_has_no_back_button_test() {
  assert !string.contains(html_of(frame(route.Plans)), "All plans")
}

pub fn the_app_bar_shows_the_title_it_is_given_test() {
  let html =
    html_of(shell.Frame(..frame(route.Plan("p1")), title: "Autumn 10k"))
  assert string.contains(html, "<h1>Autumn 10k</h1>")
}

pub fn a_running_sync_shows_a_progress_bar_test() {
  assert string.contains(
    html_of(shell.Frame(..frame(route.Home), syncing: True)),
    "role=\"progressbar\"",
  )
  assert !string.contains(html_of(frame(route.Home)), "progressbar")
}

pub fn being_offline_shows_an_icon_in_the_app_bar_test() {
  let offline = html_of(shell.Frame(..frame(route.Home), online: False))
  assert string.contains(offline, "offline-indicator")
  assert string.contains(
    offline,
    "aria-label=\"Offline. What does this mean?\"",
  )
  assert !string.contains(html_of(frame(route.Home)), "offline-indicator")
}

pub fn sync_problems_are_a_badge_on_the_settings_tab_test() {
  let html = html_of(shell.Frame(..frame(route.Home), problems: 3))
  assert string.contains(
    html,
    "Settings<span class=\"visually-hidden\">, 3 sync problems",
  )
  assert !string.contains(html_of(frame(route.Home)), "nav-badge")
}

pub fn a_plan_or_athlete_page_has_the_medium_app_bar_test() {
  assert string.contains(html_of(frame(route.Plan("p1"))), "bar bar-medium")
  assert string.contains(html_of(frame(route.Athlete("a1"))), "bar bar-medium")
  assert !string.contains(html_of(frame(route.Plans)), "bar-medium")
}
