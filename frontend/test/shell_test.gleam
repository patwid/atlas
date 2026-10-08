import atlas/route
import atlas/shell
import gleam/string
import lustre/element
import lustre/element/html

fn html_of(r: route.Route, syncing: Bool) -> String {
  element.to_string(shell.view(r, True, False, syncing, html.text("")))
}

pub fn a_page_inside_a_tab_has_a_back_button_to_its_list_test() {
  let plan = html_of(route.Plan("p1"), False)
  assert string.contains(plan, "aria-label=\"All plans\"")
  assert string.contains(plan, "href=\"/plans\"")
  assert string.contains(
    html_of(route.Athlete("a1"), False),
    "aria-label=\"All athletes\"",
  )
}

pub fn a_settings_page_goes_back_to_all_settings_test() {
  let zones = html_of(route.SettingsPage(route.Zones), False)
  assert string.contains(zones, "aria-label=\"All settings\"")
  assert string.contains(zones, "Training zones")
}

pub fn a_tab_has_no_back_button_test() {
  let plans = html_of(route.Plans, False)
  assert !string.contains(plans, "All plans")
}

pub fn a_running_sync_shows_a_progress_bar_test() {
  assert string.contains(html_of(route.Today, True), "role=\"progressbar\"")
  assert !string.contains(html_of(route.Today, False), "progressbar")
}

pub fn being_offline_shows_a_banner_test() {
  let offline =
    element.to_string(shell.view(
      route.Today,
      False,
      False,
      False,
      html.text(""),
    ))
  assert string.contains(offline, "banner-offline")
  assert string.contains(offline, "kept on this device")
  assert !string.contains(html_of(route.Today, False), "banner-offline")
}
