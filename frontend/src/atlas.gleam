//// Atlas: an offline-capable PWA for running training. This is the app shell (ADR 0013) with
//// sign-in (ADR 0017): routing, the page frame, the online indicator and the session.

import atlas/activities_page
import atlas/api
import atlas/assignments_page
import atlas/athletes_page
import atlas/auth.{type Session}
import atlas/clock
import atlas/coaches_page
import atlas/collection
import atlas/grants
import atlas/http
import atlas/online
import atlas/person_finder
import atlas/plan
import atlas/plan_copy
import atlas/plans_page
import atlas/pwa
import atlas/random
import atlas/route.{type Route}
import atlas/shares
import atlas/sharing_page
import atlas/shell
import atlas/signin
import atlas/storage
import atlas/strava_page
import atlas/sync
import atlas/syncing
import atlas/timer
import atlas/today
import atlas/today_page
import atlas/ui/banner
import atlas/ui/button
import atlas/ui/icon
import atlas/ui/interaction
import atlas/ui/layout
import atlas/ui/snackbar
import atlas/ui/tabs
import atlas/workouts_page
import atlas/zones_page
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri.{type Uri}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem

pub const session_key = "atlas.session"

pub type Auth {
  SignedOut(form: signin.Form)
  SignedIn(session: Session)
}

pub type Model {
  Model(
    route: Route,
    online: Bool,
    auth: Auth,
    syncing: syncing.State,
    plans: plans_page.Model,
    workouts: workouts_page.Model,
    assignments: assignments_page.Model,
    coaches: coaches_page.Model,
    activities: activities_page.Model,
    daily: today_page.Model,
    strava: strava_page.Model,
    sharing: sharing_page.Model,
    zones: zones_page.Model,
    /// The app's own snackbar, about the connection (ADR 0055): its number and text.
    notice: Option(#(Int, String)),
    /// How many such messages have been shown, so that a timer only closes the one it was started for.
    notices_shown: Int,
  )
}

pub type Msg {
  RouteChanged(Uri)
  OnlineChanged(Bool)
  OfflineInfoClicked
  NoticeClosed
  NoticeExpired(Int)
  EmailChanged(String)
  PasswordChanged(String)
  SignInSubmitted
  SignInResponded(http.Response)
  RefreshResponded(http.Response)
  SignOutClicked
  Syncing(syncing.Msg)
  PlansPage(plans_page.Msg)
  WorkoutsPage(workouts_page.Msg)
  AssignmentsPage(assignments_page.Msg)
  CoachesPage(coaches_page.Msg)
  ActivitiesPage(activities_page.Msg)
  TodayPage(today_page.Msg)
  StravaPage(strava_page.Msg)
  SharingPage(sharing_page.Msg)
  ZonesPage(zones_page.Msg)
  ProblemsDismissed
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let route =
    modem.initial_uri()
    |> result.map(route.parse)
    |> result.unwrap(route.Today)
  let auth = case
    storage.get(session_key) |> result.try(auth.session_from_json)
  {
    Ok(session) -> SignedIn(session)
    Error(Nil) -> SignedOut(signin.empty())
  }
  let is_online = online.is_online()
  let #(syncing_state, load) = load_device_data(auth, syncing.new())
  // Strava's redirect brings the user back to Settings with the result in the address.
  let returned =
    modem.initial_uri()
    |> result.map(route.strava_result)
    |> result.unwrap(None)
  // It lands on Strava's own Settings page (ADR 0049); the server's return address stays `/settings`.
  let strava_page_route = route.SettingsPage(route.Strava)
  let #(route, strava_start) = case auth, returned {
    SignedIn(_), Some(result) -> #(
      strava_page_route,
      effect.batch([
        send(StravaPage(strava_page.Returned(result))),
        // The address is cleaned so that a reload does not repeat the message.
        modem.replace(route.to_path(strava_page_route), None, None),
      ]),
    )
    SignedIn(_), None ->
      case route == strava_page_route {
        True -> #(route, send(StravaPage(strava_page.Refresh)))
        False -> #(route, effect.none())
      }
    SignedOut(_), _ -> #(route, effect.none())
  }
  #(
    Model(
      route:,
      online: is_online,
      auth:,
      syncing: syncing_state,
      plans: plans_page.new(),
      workouts: workouts_page.new(),
      assignments: assignments_page.new(),
      coaches: coaches_page.new(),
      activities: activities_page.new(),
      daily: today_page.new(),
      strava: strava_page.new(),
      sharing: sharing_page.new(),
      zones: zones_page.new(),
      notice: None,
      notices_shown: 0,
    ),
    effect.batch([
      modem.init(RouteChanged),
      online.listen(OnlineChanged),
      pwa.register_service_worker(),
      interaction.install(),
      load,
      strava_start,
      case is_online {
        True -> refresh_if_due(auth)
        False -> effect.none()
      },
    ]),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    RouteChanged(uri) -> {
      let next = route.parse(uri)
      // Another plan opens on its calendar (ADR 0058).
      let plans = case next == model.route {
        True -> model.plans
        False -> plans_page.Model(..model.plans, tab: "calendar")
      }
      #(
        Model(..model, route: next, plans: plans),
        // The Strava state is looked up when its Settings page is opened.
        case next, model.auth {
          route.SettingsPage(route.Strava), SignedIn(_) ->
            send(StravaPage(strava_page.Refresh))
          _, _ -> effect.none()
        },
      )
    }

    // Coming back online is when an expired or soon-to-expire session gets refreshed.
    OnlineChanged(is_online) -> {
      let #(model, shown) =
        notify(Model(..model, online: is_online), case is_online {
          True -> "Back online. Your changes are being synced."
          False -> offline_text
        })
      #(model, case is_online {
        True ->
          effect.batch([
            shown,
            refresh_if_due(model.auth),
            effect.from(fn(dispatch) { dispatch(Syncing(syncing.Kick)) }),
          ])
        False -> shown
      })
    }

    OfflineInfoClicked -> notify(model, offline_text)
    NoticeClosed -> #(Model(..model, notice: None), effect.none())
    NoticeExpired(n) ->
      case model.notice {
        Some(#(shown, _)) if shown == n -> #(
          Model(..model, notice: None),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }

    EmailChanged(email) ->
      with_form(model, fn(form) { signin.Form(..form, email: email) })
    PasswordChanged(password) ->
      with_form(model, fn(form) { signin.Form(..form, password: password) })

    SignInSubmitted ->
      case model.auth {
        SignedOut(form) if form.busy -> #(model, effect.none())
        SignedOut(form) ->
          case form.email == "" || form.password == "" {
            True -> #(
              Model(
                ..model,
                auth: SignedOut(
                  signin.Form(
                    ..form,
                    error: Some("Enter your e-mail and password."),
                  ),
                ),
              ),
              effect.none(),
            )
            False -> #(
              Model(
                ..model,
                auth: SignedOut(signin.Form(..form, busy: True, error: None)),
              ),
              http.send(
                api.sign_in(form.email, form.password),
                None,
                SignInResponded,
              ),
            )
          }
        SignedIn(_) -> #(model, effect.none())
      }

    SignInResponded(response) ->
      case
        model.auth,
        response.status,
        auth.session_from_response(response.body)
      {
        SignedOut(_), 200, Ok(session) -> {
          let #(syncing_state, load) =
            load_device_data(SignedIn(session), model.syncing)
          #(
            Model(
              ..model,
              auth: SignedIn(session),
              syncing: syncing_state,
              plans: plans_page.new(),
              workouts: workouts_page.new(),
              assignments: assignments_page.new(),
              coaches: coaches_page.new(),
              activities: activities_page.new(),
              daily: today_page.new(),
              strava: strava_page.new(),
              sharing: sharing_page.new(),
              zones: zones_page.new(),
            ),
            effect.batch([remember(session), load]),
          )
        }
        SignedOut(form), status, _ -> #(
          Model(
            ..model,
            auth: SignedOut(
              signin.Form(
                ..form,
                password: "",
                busy: False,
                error: Some(auth.sign_in_error(status, response.body)),
              ),
            ),
          ),
          effect.none(),
        )
        SignedIn(_), _, _ -> #(model, effect.none())
      }

    RefreshResponded(response) ->
      case model.auth, response.status {
        SignedIn(_), 200 -> use_refreshed_session(model, response.body)
        // The server no longer accepts the token. Nothing else is deleted: local data stays
        // for the next sign-in of the same user (ADR 0017).
        SignedIn(_), 401 -> session_ended(model)
        // Offline, a server hiccup or anything else: stay signed in and try again later.
        _, _ -> #(model, effect.none())
      }

    SignOutClicked -> #(
      Model(
        ..model,
        auth: SignedOut(signin.empty()),
        syncing: syncing.reset(model.syncing),
        plans: plans_page.new(),
        workouts: workouts_page.new(),
        assignments: assignments_page.new(),
        coaches: coaches_page.new(),
        activities: activities_page.new(),
        daily: today_page.new(),
        strava: strava_page.new(),
        sharing: sharing_page.new(),
        zones: zones_page.new(),
      ),
      forget(),
    )

    Syncing(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let context =
            syncing.Context(
              session.token,
              clock.now_seconds(),
              clock.utc_offset_minutes(),
            )
          let #(state, inner_effect, notices) =
            syncing.update(model.syncing, inner, context)
          let #(next, app_effect) =
            list.fold(
              notices,
              #(Model(..model, syncing: state), effect.none()),
              fn(acc, notice) {
                let #(current, effects) = acc
                let #(changed, more) = on_notice(current, notice)
                #(changed, effect.batch([effects, more]))
              },
            )
          // Records changed on the device: the screens read them again.
          let refresh = case state.revision != model.syncing.revision {
            True ->
              effect.batch([
                effect.map(plans_page.refresh(), PlansPage),
                effect.map(workouts_page.refresh(), WorkoutsPage),
                effect.map(assignments_page.refresh(), AssignmentsPage),
                effect.map(coaches_page.refresh(), CoachesPage),
                effect.map(activities_page.refresh(), ActivitiesPage),
                effect.map(today_page.refresh(), TodayPage),
                effect.map(sharing_page.refresh(), SharingPage),
                effect.map(zones_page.refresh(), ZonesPage),
              ])
            False -> effect.none()
          }
          #(
            next,
            effect.batch([
              effect.map(inner_effect, Syncing),
              app_effect,
              refresh,
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    PlansPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            plans_page.update(model.plans, inner, session.user_id)
          let #(state, action_effects, page_model) =
            perform(model, session, model.syncing, page_model, actions)
          #(
            Model(..model, plans: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, PlansPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    WorkoutsPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(on_screen, can_edit) = plan_on_screen(model, session)
          let #(page_model, page_effect, actions) =
            workouts_page.update(model.workouts, inner, on_screen, can_edit)
          let #(state, action_effects) =
            perform_workouts(model.syncing, actions)
          #(
            Model(..model, workouts: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, WorkoutsPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    CoachesPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let me =
            grants.Person(session.user_id, case session.name {
              "" -> session.email
              name -> name
            })
          let #(page_model, page_effect, actions) =
            coaches_page.update(model.coaches, inner, me)
          let #(state, action_effects) = perform_coaches(model.syncing, actions)
          // The lookup is a request, not a record: it is sent here and answered in a message.
          let lookups =
            list.filter_map(actions, fn(action) {
              case action {
                coaches_page.LookUp(email) ->
                  Ok(effect.map(
                    http.send(
                      api.lookup_user(email),
                      Some(session.token),
                      fn(response) {
                        coaches_page.Finder(person_finder.LookupAnswered(
                          response,
                        ))
                      },
                    ),
                    CoachesPage,
                  ))
                _ -> Error(Nil)
              }
            })
          #(
            Model(..model, coaches: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, CoachesPage),
              effect.map(effect.batch(action_effects), Syncing),
              ..lookups
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    AssignmentsPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let context = assignments_context(model, session)
          let #(page_model, page_effect, actions) =
            assignments_page.update(model.assignments, inner, context)
          // Nothing is written without a plan on screen.
          let actions = case context.plan_id {
            "" -> []
            _ -> actions
          }
          let #(state, action_effects) =
            perform_assignments(model.syncing, actions)
          #(
            Model(..model, assignments: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, AssignmentsPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    ActivitiesPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            activities_page.update(
              model.activities,
              inner,
              activities_context(session),
            )
          let #(state, action_effects) =
            perform_activities(model.syncing, actions)
          #(
            Model(..model, activities: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, ActivitiesPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    TodayPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            today_page.update(model.daily, inner, today_inputs(model, session))
          let #(state, action_effects) = perform_matches(model.syncing, actions)
          #(
            Model(..model, daily: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, TodayPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    StravaPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            strava_page.update(model.strava, inner)
          #(
            Model(..model, strava: page_model),
            effect.batch([
              effect.map(page_effect, StravaPage),
              ..list.map(actions, fn(action) { strava_effect(action, session) })
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    ZonesPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            zones_page.update(model.zones, inner, session.user_id)
          let #(state, action_effects) = perform_zones(model.syncing, actions)
          #(
            Model(..model, zones: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, ZonesPage),
              effect.map(effect.batch(action_effects), Syncing),
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    SharingPage(inner) ->
      case model.auth {
        SignedIn(session) -> {
          let #(page_model, page_effect, actions) =
            sharing_page.update(
              model.sharing,
              inner,
              sharing_context(model, session),
            )
          let #(state, action_effects) = perform_shares(model.syncing, actions)
          // The lookup is a request, not a record: it is sent here and answered in a message.
          let lookups =
            list.filter_map(actions, fn(action) {
              case action {
                sharing_page.LookUp(email) ->
                  Ok(effect.map(
                    http.send(
                      api.lookup_user(email),
                      Some(session.token),
                      fn(response) {
                        sharing_page.Finder(person_finder.LookupAnswered(
                          response,
                        ))
                      },
                    ),
                    SharingPage,
                  ))
                _ -> Error(Nil)
              }
            })
          #(
            Model(..model, sharing: page_model, syncing: state),
            effect.batch([
              effect.map(page_effect, SharingPage),
              effect.map(effect.batch(action_effects), Syncing),
              ..lookups
            ]),
          )
        }
        SignedOut(_) -> #(model, effect.none())
      }

    ProblemsDismissed -> #(
      Model(..model, syncing: syncing.dismiss_problems(model.syncing)),
      effect.none(),
    )
  }
}

/// The plan whose screen is open, and whether the user may change it (only the owner may).
/// Without an open plan nothing can be changed.
fn plan_on_screen(
  model: Model,
  session: Session,
) -> #(option.Option(plan.Plan), Bool) {
  case model.route {
    route.Plan(id) ->
      case list.find(model.plans.plans, fn(p) { p.id == id }) {
        Ok(found) -> #(Some(found), found.owner_id == session.user_id)
        Error(Nil) -> #(None, False)
      }
    _ -> #(None, False)
  }
}

/// What the schedule of the open plan needs to know. A plan can be started when it is the user's own
/// or public (the server's rule); only then can athletes be chosen too.
fn assignments_context(
  model: Model,
  session: Session,
) -> assignments_page.Context {
  let today = clock.today()
  case model.route {
    route.Plan(id) ->
      case list.find(model.plans.plans, fn(p) { p.id == id }) {
        Ok(found) -> {
          let can_start =
            found.owner_id == session.user_id
            || found.visibility == plan.Public
            || shares.is_shared_with(model.sharing.shares, id, session.user_id)
          assignments_page.Context(
            id,
            session.user_id,
            case can_start {
              True -> grants.athletes_of(model.coaches.grants, session.user_id)
              False -> []
            },
            today,
            can_start,
          )
        }
        Error(Nil) ->
          assignments_page.Context(id, session.user_id, [], today, False)
      }
    _ -> assignments_page.Context("", session.user_id, [], today, False)
  }
}

/// Everything the Today screen works from, read from what the other screens already hold.
fn today_inputs(model: Model, session: Session) -> today.Inputs {
  today.Inputs(
    user_id: session.user_id,
    today: clock.today(),
    assignments: model.assignments.rows,
    workouts: list.map(model.workouts.rows, fn(row) { row.workout }),
    plans: model.plans.plans,
    activities: model.activities.rows,
    matches: model.daily.matches,
    offset_at: clock.utc_offset_at_utc,
  )
}

/// The plan whose screen is open, for sharing: only its owner may share it.
fn sharing_context(model: Model, session: Session) -> sharing_page.Context {
  let me =
    grants.Person(session.user_id, case session.name {
      "" -> session.email
      name -> name
    })
  case model.route {
    route.Plan(id) ->
      case list.find(model.plans.plans, fn(p) { p.id == id }) {
        Ok(found) ->
          sharing_page.Context(id, me, found.owner_id == session.user_id)
        Error(Nil) -> sharing_page.Context(id, me, False)
      }
    _ -> sharing_page.Context("", me, False)
  }
}

/// Carries out what the user did with who a plan is shared with.
fn perform_shares(
  state: syncing.State,
  actions: List(sharing_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    case action {
      sharing_page.Share(id, fields) -> {
        let #(next, effect) =
          syncing.create(current, collection.PlanShares, id, fields)
        #(next, list.append(effects, [effect]))
      }
      sharing_page.ShareAgain(id, fields, base) -> {
        let #(next, effect) =
          syncing.edit(current, collection.PlanShares, id, fields, base)
        #(next, list.append(effects, [effect]))
      }
      sharing_page.Stop(id, base) -> {
        let #(next, effect) =
          syncing.delete(current, collection.PlanShares, id, base)
        #(next, list.append(effects, [effect]))
      }
      sharing_page.LookUp(_) -> acc
    }
  })
}

/// Carries out what the Strava section asked for: a request, a move to Strava's page, or a sync.
fn strava_effect(action: strava_page.Action, session: Session) -> Effect(Msg) {
  case action {
    strava_page.Fetch(request, reply) ->
      http.send(request, Some(session.token), fn(response) {
        StravaPage(strava_page.Answered(reply, response))
      })
    strava_page.Navigate(url) ->
      case uri.parse(url) {
        Ok(target) -> modem.load(target)
        Error(Nil) -> effect.none()
      }
    strava_page.SyncNow -> send(Syncing(syncing.Kick))
  }
}

/// A message sent to the app from inside an effect.
fn send(msg: Msg) -> Effect(Msg) {
  effect.from(fn(dispatch) { dispatch(msg) })
}

/// Carries out what the user did with links between activities and workouts.
fn perform_matches(
  state: syncing.State,
  actions: List(today_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    let #(next, effect) = case action {
      today_page.Create(id, fields) ->
        syncing.create(current, collection.Matches, id, fields)
      today_page.Edit(id, fields, base) ->
        syncing.edit(current, collection.Matches, id, fields, base)
      today_page.Delete(id, base) ->
        syncing.delete(current, collection.Matches, id, base)
    }
    #(next, list.append(effects, [effect]))
  })
}

/// What the activities screen needs from the browser: today, and the UTC offset for any moment
/// (it changes with daylight saving, so one number for the whole year would be wrong).
fn activities_context(session: Session) -> activities_page.Context {
  activities_page.Context(
    session.user_id,
    clock.today(),
    clock.utc_offset_at_local,
    clock.utc_offset_at_utc,
  )
}

/// Carries out what the user did with their activities.
fn perform_activities(
  state: syncing.State,
  actions: List(activities_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    let #(next, effect) = case action {
      activities_page.Create(id, fields) ->
        syncing.create(current, collection.Activities, id, fields)
      activities_page.Edit(id, fields, base) ->
        syncing.edit(current, collection.Activities, id, fields, base)
      activities_page.Delete(id, base) ->
        syncing.delete(current, collection.Activities, id, base)
    }
    #(next, list.append(effects, [effect]))
  })
}

/// Carries out what the user did with their coaches. (A lookup is not a record; the caller sends it.)
fn perform_coaches(
  state: syncing.State,
  actions: List(coaches_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    case action {
      coaches_page.Grant(id, fields) -> {
        let #(next, effect) =
          syncing.create(current, collection.CoachGrants, id, fields)
        #(next, list.append(effects, [effect]))
      }
      coaches_page.Revoke(id, base) -> {
        let #(next, effect) =
          syncing.delete(current, collection.CoachGrants, id, base)
        #(next, list.append(effects, [effect]))
      }
      coaches_page.LookUp(_) -> acc
    }
  })
}

/// Carries out what the user did with their training zones.
fn perform_zones(
  state: syncing.State,
  actions: List(zones_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    let #(next, effect) = case action {
      zones_page.Create(id, fields) ->
        syncing.create(current, collection.AthleteSettings, id, fields)
      zones_page.Edit(id, fields, base) ->
        syncing.edit(current, collection.AthleteSettings, id, fields, base)
    }
    #(next, list.append(effects, [effect]))
  })
}

/// Carries out what the user did with the schedule of a plan.
fn perform_assignments(
  state: syncing.State,
  actions: List(assignments_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    let #(next, effect) = case action {
      assignments_page.Create(id, fields) ->
        syncing.create(current, collection.Assignments, id, fields)
      assignments_page.Edit(id, fields, base) ->
        syncing.edit(current, collection.Assignments, id, fields, base)
      assignments_page.Delete(id, base) ->
        syncing.delete(current, collection.Assignments, id, base)
    }
    #(next, list.append(effects, [effect]))
  })
}

/// Carries out what the user did on the workouts of a plan.
fn perform_workouts(
  state: syncing.State,
  actions: List(workouts_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg))) {
  list.fold(actions, #(state, []), fn(acc, action) {
    let #(current, effects) = acc
    let #(next, effect) = case action {
      workouts_page.Create(id, fields) ->
        syncing.create(current, collection.Workouts, id, fields)
      workouts_page.Edit(id, fields, base) ->
        syncing.edit(current, collection.Workouts, id, fields, base)
      workouts_page.Delete(id, base) ->
        syncing.delete(current, collection.Workouts, id, base)
      workouts_page.EditPlan(id, fields, base) ->
        syncing.edit(current, collection.Plans, id, fields, base)
    }
    #(next, list.append(effects, [effect]))
  })
}

/// Carries out what the user did on the plans screens, through the sync runner. A copy needs the plan's
/// workouts, which the app holds, so it is made here, and the screen is told how it went.
fn perform(
  model: Model,
  session: Session,
  state: syncing.State,
  page_model: plans_page.Model,
  actions: List(plans_page.Action),
) -> #(syncing.State, List(Effect(syncing.Msg)), plans_page.Model) {
  list.fold(actions, #(state, [], page_model), fn(acc, action) {
    let #(current, effects, page) = acc
    case action {
      plans_page.Create(id, fields) -> {
        let #(next, effect) =
          syncing.create(current, collection.Plans, id, fields)
        #(next, list.append(effects, [effect]), page)
      }
      plans_page.Edit(id, fields, base) -> {
        let #(next, effect) =
          syncing.edit(current, collection.Plans, id, fields, base)
        #(next, list.append(effects, [effect]), page)
      }
      plans_page.Delete(id, base) -> {
        let #(next, effect) =
          syncing.delete(current, collection.Plans, id, base)
        #(next, list.append(effects, [effect]), page)
      }
      plans_page.Copy(source_id) ->
        copy_plan(model, session, current, effects, page, source_id)
    }
  })
}

/// Makes a private copy of a plan with all its workouts. The plan is created first and its workouts after
/// it, in order, so the server has the plan before it is asked to attach workouts to it.
fn copy_plan(
  model: Model,
  session: Session,
  state: syncing.State,
  effects: List(Effect(syncing.Msg)),
  page: plans_page.Model,
  source_id: String,
) -> #(syncing.State, List(Effect(syncing.Msg)), plans_page.Model) {
  let report = fn(message) {
    let #(next, _, _) = plans_page.update(page, message, session.user_id)
    next
  }
  case
    list.find(model.plans.plans, fn(p) { p.id == source_id }),
    model.workouts.loaded
  {
    Ok(source), True -> {
      let copy =
        plan_copy.build(
          source,
          workouts_page.rows_of(model.workouts, source_id),
          session.user_id,
          random.new_id,
        )
      let #(with_plan, plan_effect) =
        syncing.create(state, collection.Plans, copy.plan_id, copy.plan_fields)
      let #(finished, workout_effects) =
        list.fold(copy.workouts, #(with_plan, []), fn(inner, item) {
          let #(current, made) = inner
          let #(next, effect) =
            syncing.create(current, collection.Workouts, item.0, item.1)
          #(next, list.append(made, [effect]))
        })
      #(
        finished,
        list.append(effects, [plan_effect, ..workout_effects]),
        report(plans_page.CopyMade(source_id, copy.plan_id)),
      )
    }
    Ok(_), False -> #(
      state,
      effects,
      report(plans_page.CopyFailed(
        source_id,
        "The workouts of this plan are still loading. Try again in a moment.",
      )),
    )
    Error(Nil), _ -> #(
      state,
      effects,
      report(plans_page.CopyFailed(
        source_id,
        "This plan is no longer on this device.",
      )),
    )
  }
}

/// What the app does about the engine's notices. Conflicts and rejections are handled in `syncing`.
fn on_notice(model: Model, notice: sync.Notice) -> #(Model, Effect(Msg)) {
  case notice {
    sync.SessionRefreshed(body) -> use_refreshed_session(model, body)
    sync.SignInRequired -> session_ended(model)
    _ -> #(model, effect.none())
  }
}

/// A fresh token from a refresh. It must stay the same account; anything else is ignored.
fn use_refreshed_session(model: Model, body: String) -> #(Model, Effect(Msg)) {
  case model.auth, auth.session_from_response(body) {
    SignedIn(session), Ok(fresh) if fresh.user_id == session.user_id -> {
      let updated = auth.with_token(session, fresh.token)
      #(Model(..model, auth: SignedIn(updated)), remember(updated))
    }
    _, _ -> #(model, effect.none())
  }
}

/// The server no longer accepts the token. Nothing else is deleted: local data and unsent
/// changes stay for the next sign-in of the same user (ADR 0017, 0019).
fn session_ended(model: Model) -> #(Model, Effect(Msg)) {
  case model.auth {
    SignedIn(_) -> #(
      Model(
        ..model,
        auth: SignedOut(
          signin.Form(
            ..signin.empty(),
            error: Some("Your session expired. Sign in again."),
          ),
        ),
        syncing: syncing.reset(model.syncing),
        plans: plans_page.new(),
        workouts: workouts_page.new(),
        assignments: assignments_page.new(),
        coaches: coaches_page.new(),
        activities: activities_page.new(),
        daily: today_page.new(),
        strava: strava_page.new(),
        sharing: sharing_page.new(),
        zones: zones_page.new(),
      ),
      forget(),
    )
    SignedOut(_) -> #(model, effect.none())
  }
}

/// Opens the device database for a signed-in user. Nothing happens when signed out.
fn load_device_data(
  state: Auth,
  current: syncing.State,
) -> #(syncing.State, Effect(Msg)) {
  case state {
    SignedIn(session) -> {
      let #(next, load) = syncing.load(current, session.user_id)
      #(next, effect.map(load, Syncing))
    }
    SignedOut(_) -> #(current, effect.none())
  }
}

fn with_form(
  model: Model,
  change: fn(signin.Form) -> signin.Form,
) -> #(Model, Effect(Msg)) {
  case model.auth {
    SignedOut(form) -> #(
      Model(..model, auth: SignedOut(change(form))),
      effect.none(),
    )
    SignedIn(_) -> #(model, effect.none())
  }
}

fn remember(session: Session) -> Effect(Msg) {
  effect.from(fn(_) { storage.set(session_key, auth.session_to_json(session)) })
}

fn forget() -> Effect(Msg) {
  effect.from(fn(_) { storage.remove(session_key) })
}

/// Asks the server for a fresh token when the stored one is close to expiring (or already expired).
/// The clock is read when the effect runs, so `update` stays free of the current time.
fn refresh_if_due(state: Auth) -> Effect(Msg) {
  case state {
    SignedOut(_) -> effect.none()
    SignedIn(session) ->
      effect.from(fn(dispatch) {
        case auth.should_refresh(session.token, clock.now_seconds()) {
          True ->
            http.perform(api.refresh(), Some(session.token), fn(response) {
              dispatch(RefreshResponded(response))
            })
          False -> Nil
        }
      })
  }
}

const offline_text =
  "You are offline. Your changes are kept on this device and synced when you are back online."

/// Shows a snackbar about the connection, closed by itself after 6 seconds (ADR 0055): it has no action, so it
/// may go, and the app bar's icon brings it back.
fn notify(model: Model, text: String) -> #(Model, Effect(Msg)) {
  let n = model.notices_shown + 1
  #(
    Model(..model, notice: Some(#(n, text)), notices_shown: n),
    timer.after(6, NoticeExpired(n)),
  )
}

pub fn view(model: Model) -> Element(Msg) {
  case model.auth {
    SignedOut(form) ->
      signin.view(form, EmailChanged, PasswordChanged, SignInSubmitted)
    SignedIn(session) ->
      shell.view(
        shell.Frame(
          route: model.route,
          title: title(model, session),
          online: model.online,
          coaching: grants.athletes_of(model.coaches.grants, session.user_id)
            != [],
          syncing: syncing.is_busy(model.syncing),
          problems: list.length(model.syncing.problems),
          on_offline_info: OfflineInfoClicked,
          actions: case model.route {
            route.Plan(id) ->
              element.map(
                plans_page.app_bar_actions(model.plans, id, session.user_id),
                PlansPage,
              )
            _ -> element.none()
          },
          main_action: main_action(model, session),
        ),
        element.fragment([
          page(model, session),
          case model.notice {
            Some(#(_, text)) -> snackbar.view(text, None, NoticeClosed)
            None -> element.none()
          },
        ]),
      )
  }
}

/// The screen's main action in the app bar from the medium window class (ADR 0068); the page draws the same action as
/// a FAB on a phone. On a plan's page it is the open tab's.
fn main_action(model: Model, session: Session) -> Element(Msg) {
  case model.route {
    route.Plans ->
      element.map(
        button.app_bar_for(plans_page.main_action(model.plans)),
        PlansPage,
      )
    route.Activities ->
      element.map(
        button.app_bar_for(activities_page.main_action(model.activities)),
        ActivitiesPage,
      )
    route.Plan(id) ->
      case list.find(model.plans.plans, fn(p) { p.id == id }), model.plans.tab {
        Ok(found), "calendar" ->
          element.map(
            button.app_bar_for(workouts_page.main_action(
              model.workouts,
              found,
              found.owner_id == session.user_id,
            )),
            WorkoutsPage,
          )
        Ok(_), "schedule" ->
          element.map(
            button.app_bar_for(assignments_page.main_action(
              model.assignments,
              assignments_context(model, session),
            )),
            AssignmentsPage,
          )
        _, _ -> element.none()
      }
    _ -> element.none()
  }
}

/// The app bar's title: the plan's or athlete's name on their page, else the page's own (ADR 0055).
fn title(model: Model, session: Session) -> String {
  case model.route {
    route.Plan(id) ->
      case list.find(model.plans.plans, fn(p) { p.id == id }) {
        Ok(found) -> found.title
        Error(Nil) -> route.title(model.route)
      }
    route.Athlete(id) ->
      case
        list.find(
          grants.athletes_of(model.coaches.grants, session.user_id),
          fn(person) { person.id == id },
        )
      {
        Ok(person) -> person.name
        Error(Nil) -> route.title(model.route)
      }
    other -> route.title(other)
  }
}

fn page(model: Model, session: Session) -> Element(Msg) {
  case model.route {
    route.Today ->
      element.map(
        today_page.view(model.daily, today_inputs(model, session)),
        TodayPage,
      )
    route.Plans ->
      element.map(
        plans_page.view_list_with(model.plans, session.user_id, fn(p) {
          shares.shared_by(model.sharing.shares, p.id, session.user_id)
        }),
        PlansPage,
      )
    route.Plan(id) -> {
      let detail =
        element.map(
          plans_page.view_detail_with(model.plans, id, session.user_id, fn(p) {
            shares.shared_by(model.sharing.shares, p.id, session.user_id)
          }),
          PlansPage,
        )
      case list.find(model.plans.plans, fn(p) { p.id == id }) {
        Ok(found) -> {
          let owner = found.owner_id == session.user_id
          let calendar =
            element.map(
              workouts_page.view(model.workouts, found, owner),
              WorkoutsPage,
            )
          let schedule =
            element.map(
              assignments_page.view(
                model.assignments,
                assignments_context(model, session),
                list.map(workouts_page.rows_of(model.workouts, id), fn(row) {
                  row.workout
                }),
                model.coaches.grants,
              ),
              AssignmentsPage,
            )
          // The plan's sections are tabs (ADR 0058); only the owner shares a plan.
          html.div([], [
            detail,
            tabs.view(
              "plan",
              model.plans.tab,
              list.flatten([
                [
                  tabs.Tab("calendar", "Calendar", calendar),
                  tabs.Tab("schedule", "Schedule", schedule),
                ],
                case owner {
                  True -> [
                    tabs.Tab(
                      "sharing",
                      "Sharing",
                      element.map(
                        sharing_page.view(
                          model.sharing,
                          sharing_context(model, session),
                        ),
                        SharingPage,
                      ),
                    ),
                  ]
                  False -> []
                },
              ]),
              fn(tab) { PlansPage(plans_page.TabSelected(tab)) },
            ),
          ])
        }
        Error(Nil) -> detail
      }
    }
    route.Activities ->
      element.map(
        activities_page.view(model.activities, activities_context(session)),
        ActivitiesPage,
      )
    // Settings is a list whose rows open a section's page, one pane at every width (ADR 0065).
    route.Settings ->
      html.div([], [
        sync_banners(model.syncing),
        settings_list(session, model.syncing),
      ])
    route.SettingsPage(page) ->
      html.div([], [
        sync_banners(model.syncing),
        case page {
          route.Zones ->
            element.map(
              zones_page.view(model.zones, session.user_id),
              ZonesPage,
            )
          route.Coaches ->
            element.map(
              coaches_page.view(model.coaches, session.user_id),
              CoachesPage,
            )
          route.Strava ->
            element.map(strava_page.view(model.strava), StravaPage)
        },
      ])
    route.Athletes ->
      athletes_page.view_list(grants.athletes_of(
        model.coaches.grants,
        session.user_id,
      ))
    route.Athlete(id) -> {
      let athlete =
        list.find(
          grants.athletes_of(model.coaches.grants, session.user_id),
          fn(person) { person.id == id },
        )
      athletes_page.view_athlete(
        option.from_result(athlete),
        // The same computation as the athlete's own Today screen, for the athlete.
        today.Inputs(..today_inputs(model, session), user_id: id),
      )
    }
    route.NotFound ->
      shell.empty("Page not found", "Use the tabs below to get back.")
  }
}

/// Settings is a list (ADR 0049, 0055): the account and the sync state as rows of their own, then a row per section
/// that opens the section's page. Sync problems show at the top of every Settings page, so they are not missed.
fn settings_list(session: Session, sync_state: syncing.State) -> Element(Msg) {
  html.section([attribute.class("settings")], [
    html.ul([attribute.class("list link-list")], [
      layout.info_item(
        icon.AccountCircle,
        account_name(session),
        "Signed in",
        button.text(
          [attribute.type_("button"), event.on_click(SignOutClicked)],
          [html.text("Sign out")],
        ),
      ),
      layout.info_item(icon.Sync, "Sync", sync_text(sync_state), element.none()),
      ..list.map(route.settings_pages, fn(page) {
        let #(symbol, supporting) = case page {
          route.Zones -> #(icon.Favorite, "Heart rate, lactate and pace")
          route.Coaches -> #(icon.Group, "Who can see your training")
          route.Strava -> #(icon.Link, "Import your activities")
        }
        layout.link_item(
          route.to_path(route.SettingsPage(page)),
          symbol,
          route.settings_title(page),
          supporting,
        )
      })
    ]),
  ])
}

fn account_name(session: Session) -> String {
  case session.name {
    "" -> session.email
    name -> name <> " (" <> session.email <> ")"
  }
}

fn sync_text(sync_state: syncing.State) -> String {
  case sync_state.phase, sync_state.problems {
    syncing.Unavailable, _ ->
      "This browser could not open its local storage, so nothing is synced. Try reloading."
    syncing.Loading, _ -> "Opening the data on this device…"
    syncing.NotLoaded, _ -> "Not started."
    syncing.Ready, [] ->
      "Your data is stored on this device and synced when you are online."
    syncing.Ready, [_] -> "1 change needs your attention, see above."
    syncing.Ready, problems ->
      int.to_string(list.length(problems))
      <> " changes need your attention, see above."
  }
}

/// A full device and sync problems, as banners (ADR 0049).
fn sync_banners(sync_state: syncing.State) -> Element(Msg) {
  element.fragment([
    case sync_state.write_failed {
      True ->
        banner.view(
          [attribute.class("banner-error"), attribute.role("alert")],
          icon.ErrorOutline,
          [
            html.text(
              "Your device ran out of storage. Free some space, or recent changes may be lost.",
            ),
          ],
          [],
        )
      False -> element.none()
    },
    case sync_state.problems {
      [] -> element.none()
      problems ->
        banner.view(
          [attribute.class("problems"), attribute.role("status")],
          icon.ErrorOutline,
          [
            html.ul(
              [],
              list.map(problems, fn(message) {
                html.li([], [html.text(message)])
              }),
            ),
          ],
          [
            button.text(
              [attribute.type_("button"), event.on_click(ProblemsDismissed)],
              [html.text("Dismiss")],
            ),
          ],
        )
    },
  ])
}
