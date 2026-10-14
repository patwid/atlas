//// The plans screens: the list with a form for new plans, and a single plan with edit and delete.
//// Own state and messages, embedded by the app. Plans are read from the device database; writes
//// are returned as `Action`s for the app to carry out through the sync runner (ADR 0020, 0021).
//// Every plan is for one athlete, chosen when it is made or copied (ADR 0110).

import atlas/assignment_form
import atlas/collection
import atlas/date.{type Date}
import atlas/grants.{type Grant, type Person}
import atlas/outbox
import atlas/plan.{type Plan}
import atlas/plan_form
import atlas/random
import atlas/records
import atlas/route
import atlas/store
import atlas/ui/button
import atlas/ui/chip
import atlas/ui/date_picker
import atlas/ui/empty
import atlas/ui/error
import atlas/ui/field
import atlas/ui/focus
import atlas/ui/form_dialog
import atlas/ui/icon
import atlas/ui/layout
import atlas/ui/menu
import atlas/ui/plan_settings
import atlas/ui/progress
import atlas/ui/snackbar
import atlas/ui/undo.{type Undo}
import atlas/units
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import lustre/attribute.{class}
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem

pub type Mode {
  Browsing
  Creating
  Editing(id: String)
}

/// Where a copy of the plan on screen stands.
pub type CopyState {
  NoCopy
  /// Who the copy is for is being chosen: the user or one of their athletes (ADR 0110).
  ChoosingCopy(source_id: String, athlete_id: String)
  /// Asked for; the app is making it.
  Copying(source_id: String)
  Copied(source_id: String, new_id: String)
  CopyProblem(source_id: String, message: String)
}

pub type Model {
  Model(
    plans: List(Plan),
    /// False until the device database has been read once.
    loaded: Bool,
    mode: Mode,
    form: plan_form.Form,
    /// A delete that can still be undone (ADR 0056).
    undo: Undo,
    copy: CopyState,
    /// Whether a long description is shown in full, not cut to three lines (ADR 0076).
    description_open: Bool,
    /// The plan just created here, which opens at once: until the device database has it, its page shows
    /// it loading rather than missing.
    created: Option(String),
    /// The start date's picker (ADR 0054, 0108).
    date_picker: date_picker.State,
    /// The day of the last update: a new plan starts on the Monday after it, and the picker marks it.
    today: Date,
  )
}

pub type Msg {
  /// Read the plans from the device database again.
  Refresh
  PlansRead(Result(List(Dynamic), Nil))
  NewClicked
  EditClicked(String)
  CancelClicked
  TitleChanged(String)
  DescriptionChanged(String)
  AthleteChanged(String)
  StartChanged(String)
  /// The picker's button was pressed; it opens on what the field holds now (ADR 0054).
  StartPickerOpened
  StartPicker(date_picker.Msg)
  BaseWeeksChanged(String)
  PreCompetitionWeeksChanged(String)
  CompetitionWeeksChanged(String)
  GoalChanged(String)
  Submitted
  /// Deletes at once and goes back to the list, with Undo for a few seconds (ADR 0056).
  DeleteClicked(String)
  UndoClicked
  DeleteExpired(Int)
  CopyClicked(String)
  CopyForChanged(String)
  CopyConfirmed
  CopyCancelled
  /// The app made the copy: its plan has this ID.
  CopyMade(String, String)
  CopyFailed(String, String)
  CopyAgainClicked
  /// More or Less under a long description.
  DescriptionToggled
}

/// A change the user made. The app performs it with the sync runner.
pub type Action {
  Create(id: String, fields: outbox.Fields)
  /// The athlete of a plan just created, written after it (ADR 0110).
  Assign(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
  /// Copy the plan with its workouts into the user's plans, for this athlete. The app builds the records and reports
  /// back with `CopyMade`.
  Copy(source_id: String, athlete_id: String)
}

/// How a plan relates to the user: theirs for themselves, theirs for an athlete, or a coach's for them (ADR 0110).
pub type Relation {
  ForMe
  ForAthlete(name: String)
  FromCoach(name: String)
}

pub fn new() -> Model {
  Model(
    [],
    False,
    Browsing,
    plan_form.empty(date.Date(2026, 1, 1), ""),
    undo.new(),
    NoCopy,
    False,
    None,
    date_picker.new(),
    date.Date(2026, 1, 1),
  )
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Plans, fn(result) { dispatch(PlansRead(result)) })
  })
}

/// `athletes`: those who granted the user access, whom a plan can be made or copied for.
pub fn update(
  model: Model,
  msg: Msg,
  user_id: String,
  athletes: List(Person),
  today: Date,
) -> #(Model, Effect(Msg), List(Action)) {
  let model = Model(..model, today: today)
  case msg {
    Refresh -> #(model, refresh(), [])

    PlansRead(Ok(stored)) -> {
      let plans = sorted(records.live(stored, records.plan))
      // A plan that disappeared (deleted elsewhere) ends an edit of it.
      let mode = case model.mode {
        Editing(id) ->
          case find(plans, id) {
            Ok(_) -> model.mode
            Error(Nil) -> Browsing
          }
        other -> other
      }
      // Once the new plan is read back, its page no longer needs to wait for it.
      let created = case model.created {
        Some(id) ->
          case find(plans, id) {
            Ok(_) -> None
            Error(Nil) -> model.created
          }
        None -> None
      }
      #(
        Model(..model, plans: plans, loaded: True, mode: mode, created: created),
        effect.none(),
        [],
      )
    }
    PlansRead(Error(Nil)) -> #(model, effect.none(), [])

    NewClicked -> #(
      Model(..model, mode: Creating, form: plan_form.empty(today, user_id)),
      // The form opens in a dialog (ADR 0057); its first field takes the focus.
      focus.soon("plan-title"),
      [],
    )

    EditClicked(id) ->
      case find(model.plans, id) {
        Ok(found) if found.owner_id == user_id -> #(
          Model(..model, mode: Editing(id), form: plan_form.from_plan(found)),
          effect.none(),
          [],
        )
        _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(
      Model(..model, mode: Browsing, form: plan_form.empty(today, user_id)),
      effect.none(),
      [],
    )

    TitleChanged(title) ->
      change_form(
        model,
        plan_form.Form(..model.form, title: title, error: None),
      )
    DescriptionChanged(description) ->
      change_form(
        model,
        plan_form.Form(..model.form, description: description, error: None),
      )
    AthleteChanged(id) ->
      change_form(
        model,
        plan_form.Form(..model.form, athlete_id: id, error: None),
      )

    StartChanged(text) ->
      change_form(
        model,
        plan_form.Form(..model.form, start_date: text, error: None),
      )
    StartPickerOpened ->
      update(
        model,
        StartPicker(date_picker.Opened(model.form.start_date, today)),
        user_id,
        athletes,
        today,
      )
    StartPicker(inner) -> {
      let #(state, picker_effect, picked) =
        date_picker.update(start_picker_id, model.date_picker, inner)
      let model = Model(..model, date_picker: state)
      let model = case picked {
        Some(text) ->
          Model(
            ..model,
            form: plan_form.Form(..model.form, start_date: text, error: None),
          )
        None -> model
      }
      #(model, effect.map(picker_effect, StartPicker), [])
    }

    BaseWeeksChanged(value) ->
      change_settings(model, fn(s) {
        plan_form.Settings(..s, base_weeks: value)
      })
    PreCompetitionWeeksChanged(value) ->
      change_settings(model, fn(s) {
        plan_form.Settings(..s, pre_competition_weeks: value)
      })
    CompetitionWeeksChanged(value) ->
      change_settings(model, fn(s) {
        plan_form.Settings(..s, competition_weeks: value)
      })
    GoalChanged(value) ->
      change_settings(model, fn(s) { plan_form.Settings(..s, goal_km: value) })

    Submitted ->
      case plan_form.validate(model.form), model.mode {
        Error(message), _ -> #(
          Model(
            ..model,
            form: plan_form.Form(..model.form, error: Some(message)),
          ),
          effect.none(),
          [],
        )
        Ok(valid), Creating ->
          case allowed_athlete(model.form.athlete_id, user_id, athletes) {
            False -> #(
              Model(
                ..model,
                form: plan_form.Form(
                  ..model.form,
                  error: Some("You cannot make a plan for that person."),
                ),
              ),
              effect.none(),
              [],
            )
            True -> {
              let id = random.new_id()
              #(
                Model(
                  ..model,
                  mode: Browsing,
                  form: plan_form.empty(today, user_id),
                  created: Some(id),
                ),
                modem.push(route.to_path(route.Plan(id)), None, None),
                // The plan first, so the server has it before its assignment (ADR 0016).
                [
                  Create(id, plan_form.create_fields(user_id, valid)),
                  Assign(
                    random.new_id(),
                    assignment_form.create_fields(
                      id,
                      user_id,
                      model.form.athlete_id,
                    ),
                  ),
                ],
              )
            }
          }
        Ok(valid), Editing(id) ->
          case find(model.plans, id) {
            Ok(found) if found.owner_id == user_id -> {
              let fields = plan_form.changed_fields(found, valid)
              #(
                Model(
                  ..model,
                  mode: Browsing,
                  form: plan_form.empty(today, user_id),
                ),
                effect.none(),
                case dict.is_empty(fields) {
                  True -> []
                  False -> [Edit(id, fields, found.updated)]
                },
              )
            }
            _ -> #(Model(..model, mode: Browsing), effect.none(), [])
          }
        Ok(_), Browsing -> #(model, effect.none(), [])
      }

    DeleteClicked(id) ->
      case delete_of(model, user_id, id) {
        [] -> #(model, effect.none(), [])
        _ -> {
          let #(next, earlier, wait) = undo.start(model.undo, id, DeleteExpired)
          #(
            Model(..model, undo: next, mode: Browsing),
            effect.batch([
              wait,
              modem.push(route.to_path(route.Plans), None, None),
            ]),
            option.map(earlier, delete_of(model, user_id, _))
              |> option.unwrap([]),
          )
        }
      }

    UndoClicked -> #(
      Model(..model, undo: undo.cancel(model.undo)),
      effect.none(),
      [],
    )

    DeleteExpired(n) -> {
      let #(next, due) = undo.expire(model.undo, n)
      #(
        Model(..model, undo: next),
        effect.none(),
        option.map(due, delete_of(model, user_id, _)) |> option.unwrap([]),
      )
    }

    DescriptionToggled -> #(
      Model(..model, description_open: !model.description_open),
      effect.none(),
      [],
    )

    CopyClicked(id) ->
      case model.copy, find(model.plans, id), athletes {
        // One copy at a time, and no second one by a double click.
        Copying(_), _, _ -> #(model, effect.none(), [])
        Copied(source, _), _, _ if source == id -> #(model, effect.none(), [])
        // Someone who coaches chooses who the copy is for (ADR 0110).
        _, Ok(_), [_, ..] -> #(
          Model(..model, copy: ChoosingCopy(id, user_id)),
          effect.none(),
          [],
        )
        _, Ok(_), [] -> #(Model(..model, copy: Copying(id)), effect.none(), [
          Copy(id, user_id),
        ])
        _, Error(Nil), _ -> #(model, effect.none(), [])
      }

    CopyForChanged(athlete_id) ->
      case model.copy {
        ChoosingCopy(source, _) -> #(
          Model(..model, copy: ChoosingCopy(source, athlete_id)),
          effect.none(),
          [],
        )
        _ -> #(model, effect.none(), [])
      }

    CopyConfirmed ->
      case model.copy {
        ChoosingCopy(source, athlete_id) ->
          case allowed_athlete(athlete_id, user_id, athletes) {
            True -> #(Model(..model, copy: Copying(source)), effect.none(), [
              Copy(source, athlete_id),
            ])
            False -> #(Model(..model, copy: NoCopy), effect.none(), [])
          }
        _ -> #(model, effect.none(), [])
      }

    CopyCancelled -> #(Model(..model, copy: NoCopy), effect.none(), [])

    CopyMade(source, new_id) -> #(
      Model(..model, copy: Copied(source, new_id)),
      effect.none(),
      [],
    )

    CopyFailed(source, message) -> #(
      Model(..model, copy: CopyProblem(source, message)),
      effect.none(),
      [],
    )

    CopyAgainClicked -> #(Model(..model, copy: NoCopy), effect.none(), [])
  }
}

/// A plan can be for the user, or for an athlete who granted them access (the server's rule, ADR 0110).
fn allowed_athlete(
  athlete_id: String,
  user_id: String,
  athletes: List(Person),
) -> Bool {
  athlete_id == user_id
  || list.any(athletes, fn(person) { person.id == athlete_id })
}

/// Who a plan is for, or from, as seen by the user, with names from the coach grants. Someone whose grant is gone
/// is "someone".
pub fn relation(
  p: Plan,
  user_id: String,
  assignments: List(assignment_form.Row),
  all_grants: List(Grant),
) -> Relation {
  let name = fn(id) {
    grants.name_of(all_grants, id) |> option.unwrap("someone")
  }
  case p.owner_id == user_id {
    False -> FromCoach(name(p.owner_id))
    True ->
      case assignment_form.of_plan(assignments, p.id) {
        Some(row) if row.assignment.athlete_id != user_id ->
          ForAthlete(name(row.assignment.athlete_id))
        _ -> ForMe
      }
  }
}

fn change_form(
  model: Model,
  form: plan_form.Form,
) -> #(Model, Effect(Msg), List(Action)) {
  #(Model(..model, form: form), effect.none(), [])
}

fn change_settings(
  model: Model,
  change: fn(plan_form.Settings) -> plan_form.Settings,
) -> #(Model, Effect(Msg), List(Action)) {
  change_form(
    model,
    plan_form.Form(
      ..model.form,
      settings: change(model.form.settings),
      error: None,
    ),
  )
}

fn find(plans: List(Plan), id: String) -> Result(Plan, Nil) {
  list.find(plans, fn(p) { p.id == id })
}

/// By title, ignoring case, with the ID as tie breaker so the order never jumps around.
fn sorted(plans: List(Plan)) -> List(Plan) {
  list.sort(plans, fn(a, b) {
    order.lazy_break_tie(
      string.compare(string.lowercase(a.title), string.lowercase(b.title)),
      fn() { string.compare(a.id, b.id) },
    )
  })
}

// VIEWS -------------------------------------------------------------------------------------------

/// `athletes`: whom a new plan can be for; `relation` says who each plan is for or from.
pub fn view_list(
  model: Model,
  user_id: String,
  athletes: List(Person),
  relation: fn(Plan) -> Relation,
) -> Element(Msg) {
  let shown =
    model.plans
    |> list.filter(fn(p) { !undo.hides(model.undo, p.id) })
    |> list.map(fn(p) { #(p, relation(p)) })
  let #(mine, rest) = list.partition(shown, fn(item) { item.1 == ForMe })
  let #(for_athletes, from_coaches) =
    list.partition(rest, fn(item) {
      case item.1 {
        ForAthlete(_) -> True
        _ -> False
      }
    })
  html.section([class("plans")], [
    undo.snackbar(model.undo, "Plan deleted", UndoClicked, DeleteExpired),
    html.div([class("toolbar")], [
      layout.subheader("Your plans"),
      button.fab_for(main_action(model)),
    ]),
    form_view(model, model.mode == Creating, "New plan", user_id, athletes),
    case model.loaded, mine {
      False, _ -> progress.loading("Loading…")
      True, [] ->
        case model.mode {
          Creating -> element.none()
          _ ->
            empty.view(
              icon.EventNote,
              "You have no plans yet",
              "Create one with New plan.",
              None,
            )
        }
      True, plans -> plan_list(plans)
    },
    group("Your athletes' plans", for_athletes),
    group("From your coaches", from_coaches),
  ])
}

fn group(title: String, plans: List(#(Plan, Relation))) -> Element(Msg) {
  case plans {
    [] -> element.none()
    _ -> html.div([], [layout.subheader(title), plan_list(plans)])
  }
}

pub fn view_detail(
  model: Model,
  id: String,
  user_id: String,
  athletes: List(Person),
  relation: fn(Plan) -> Relation,
) -> Element(Msg) {
  case find(model.plans, id) {
    Error(Nil) ->
      html.section([class("plans")], [
        case model.loaded && model.created != Some(id) {
          False -> progress.loading("Loading…")
          True ->
            empty.view(
              icon.SearchOff,
              "This plan is not on this device",
              "It may not have synced yet, or it may have been deleted.",
              Some(empty.link(route.to_path(route.Plans), "All plans")),
            )
        },
      ])
    Ok(found) ->
      html.section([class("plans")], [
        form_view(model, model.mode == Editing(id), "Edit plan", user_id, []),
        copy_dialog(model.copy, user_id, athletes),
        // One block in one type size: who the plan is for or from, its phases, then its description; a coach's
        // plan ends with why it cannot be edited here.
        html.div([class("plan-header")], [
          chips(found),
          case relation(found) {
            ForMe -> element.none()
            ForAthlete(name) -> meta(icon.AccountCircle, "For " <> name)
            FromCoach(name) -> meta(icon.AccountCircle, "From " <> name)
          },
          case phase_chips(found) {
            [] -> element.none()
            labels ->
              html.div([class("plan-phases")], list.map(labels, chip.label))
          },
          description_view(found.description, model.description_open),
          case relation(found) {
            FromCoach(_) ->
              meta(
                icon.Lock,
                "Only they can change it. Copy it to make a version of your own.",
              )
            _ -> element.none()
          },
          copy_view(model.copy, found.id),
        ]),
      ])
  }
}

/// A line of the plan's header led by an icon.
fn meta(symbol: icon.Icon, text: String) -> Element(Msg) {
  html.p([class("plan-meta")], [icon.view(symbol), html.text(text)])
}

/// A long description is cut to three lines above the tabs, so it does not push the calendar off a phone's screen;
/// More shows the rest (ADR 0076).
fn description_view(text: String, open: Bool) -> Element(Msg) {
  let long =
    string.length(text) > 240 || list.length(string.split(text, "\n")) > 3
  case text, long {
    "", _ -> element.none()
    _, False -> html.p([class("description")], [html.text(text)])
    _, True ->
      html.div([], [
        html.p(
          [
            class("description"),
            attribute.id("plan-description"),
            attribute.classes([#("clamped", !open)]),
          ],
          [html.text(text)],
        ),
        button.text(
          [
            attribute.type_("button"),
            class("description-toggle"),
            attribute.attribute("aria-expanded", case open {
              True -> "true"
              False -> "false"
            }),
            attribute.attribute("aria-controls", "plan-description"),
            event.on_click(DescriptionToggled),
          ],
          [
            html.text(case open {
              True -> "Less"
              False -> "More"
            }),
          ],
        ),
      ])
  }
}

fn copy_view(state: CopyState, plan_id: String) -> Element(Msg) {
  case state {
    // Closing the snackbar brings the Copy button back, for another copy.
    Copied(source, new_id) if source == plan_id ->
      snackbar.view(
        "Copied to your plans.",
        Some(snackbar.Link("Open your copy", route.to_path(route.Plan(new_id)))),
        CopyAgainClicked,
      )
    CopyProblem(source, message) if source == plan_id ->
      html.div([], [
        error.message(message),
        button.tonal(
          [attribute.type_("button"), event.on_click(CopyAgainClicked)],
          [html.text("Try again")],
        ),
      ])
    Copying(source) if source == plan_id -> progress.loading("Copying…")
    _ -> element.none()
  }
}

/// Who a plan or a copy is for: Myself, or an athlete. Nothing without athletes, as it can only be the user (ADR 0110).
fn athlete_choice(
  id: String,
  value: String,
  user_id: String,
  athletes: List(Person),
  on_change: fn(String) -> Msg,
) -> Element(Msg) {
  case athletes {
    [] -> element.none()
    _ ->
      field.choose(
        id,
        "For",
        field.help(
          "It cannot be changed later; copy the plan for someone else.",
        ),
        [attribute.name("athlete"), event.on_change(on_change)],
        value,
        [
          #(user_id, "Myself"),
          ..list.map(athletes, fn(person) { #(person.id, person.name) })
        ],
      )
  }
}

const copy_form_id = "copy-form"

/// Choosing who a copy is for, when the user coaches someone (ADR 0110).
fn copy_dialog(
  state: CopyState,
  user_id: String,
  athletes: List(Person),
) -> Element(Msg) {
  let #(open, athlete_id) = case state {
    ChoosingCopy(_, athlete_id) -> #(True, athlete_id)
    _ -> #(False, user_id)
  }
  form_dialog.view(
    "copy-dialog",
    open,
    "Make a copy",
    copy_form_id,
    "Copy",
    CopyCancelled,
    [
      html.form(
        [
          attribute.id(copy_form_id),
          event.on_submit(fn(_) { CopyConfirmed }),
        ],
        [
          athlete_choice(
            "copy-athlete",
            athlete_id,
            user_id,
            athletes,
            CopyForChanged,
          ),
        ],
      ),
    ],
  )
}

/// The plan page's actions in the app bar (ADR 0058): Edit and a menu with Make a copy and Delete for its owner,
/// Copy to my plans for everyone else. Copying is not offered again while a copy is being made or just made.
pub fn app_bar_actions(
  model: Model,
  id: String,
  user_id: String,
) -> Element(Msg) {
  let copying = case model.copy {
    Copying(source) | Copied(source, _) -> source == id
    _ -> False
  }
  case find(model.plans, id) {
    Error(Nil) -> element.none()
    Ok(found) if found.owner_id == user_id ->
      button.group([
        button.icon(
          [attribute.type_("button"), event.on_click(EditClicked(id))],
          icon.Edit,
          "Edit plan",
        ),
        menu.view("plan-menu", "More for this plan", case copying {
          True -> [menu.Item(icon.Delete, "Delete", DeleteClicked(id))]
          False -> [
            menu.Item(icon.ContentCopy, "Make a copy", CopyClicked(id)),
            menu.Item(icon.Delete, "Delete", DeleteClicked(id)),
          ]
        }),
      ])
    Ok(_) ->
      case copying {
        True -> element.none()
        False ->
          button.icon(
            [attribute.type_("button"), event.on_click(CopyClicked(id))],
            icon.ContentCopy,
            "Copy to my plans",
          )
      }
  }
}

/// The delete to write for a plan of the user's own.
fn delete_of(model: Model, user_id: String, id: String) -> List(Action) {
  case find(model.plans, id) {
    Ok(found) if found.owner_id == user_id -> [Delete(id, found.updated)]
    _ -> []
  }
}

fn plan_list(plans: List(#(Plan, Relation))) -> Element(Msg) {
  layout.list(
    list.map(plans, fn(item) {
      let #(p, relation) = item
      html.li([], [
        html.div([], [
          layout.row_link(route.to_path(route.Plan(p.id)), p.title),
          chips(p),
        ]),
        case relation {
          ForMe -> element.none()
          ForAthlete(name) ->
            html.p([class("muted")], [html.text("For " <> name)])
          FromCoach(name) ->
            html.p([class("muted")], [html.text("From " <> name)])
        },
        case p.description {
          "" -> element.none()
          text -> html.p([class("muted")], [html.text(snippet(text))])
        },
      ])
    }),
  )
}

fn chips(p: Plan) -> Element(Msg) {
  chip.row([
    case p.updated {
      "" -> chip.with_icon(icon.CloudUpload, "Not synced yet")
      _ -> element.none()
    },
  ])
}

/// The start of a description for the list: one line, at most 120 characters.
pub fn snippet(text: String) -> String {
  let line = case string.split(text, "\n") {
    [first, ..] -> first
    [] -> ""
  }
  case string.length(line) > 120 {
    True -> string.slice(line, 0, 119) <> "…"
    False -> line
  }
}

const form_id = "plan-form"

const start_picker_id = "plan-start-picker"

/// Creating and editing a plan happen in a full-screen dialog (ADR 0057).
/// `athletes`: whom a new plan can be for; the choice shows only when there is someone (ADR 0110).
fn form_view(
  model: Model,
  open: Bool,
  title: String,
  user_id: String,
  athletes: List(Person),
) -> Element(Msg) {
  form_dialog.view(
    "plan-form-dialog",
    open,
    title,
    form_id,
    "Save",
    CancelClicked,
    // The picker's dialog holds a form of its own, so it sits beside this form, not in it.
    [
      form_fields(
        model.form,
        case model.mode {
          Creating -> athletes
          _ -> []
        },
        user_id,
      ),
      date_picker.view(
        start_picker_id,
        model.date_picker,
        model.today,
        StartPicker,
      ),
    ],
  )
}

fn form_fields(
  form: plan_form.Form,
  athletes: List(Person),
  user_id: String,
) -> Element(Msg) {
  // A problem shows under the field it is about (ADR 0059).
  let wrong = plan_form.error_field(form)
  let on = fn(help, field_name) {
    field.with_error(help, field_name, wrong, form.error)
  }
  html.form(
    [
      attribute.id(form_id),
      class("plan-form"),
      event.on_submit(fn(_) { Submitted }),
    ],
    [
      field.text("plan-title", "Title", on(field.plain, "title"), [
        attribute.type_("text"),
        attribute.name("title"),
        attribute.value(form.title),
        attribute.attribute("maxlength", "200"),
        attribute.required(True),
        event.on_input(TitleChanged),
      ]),
      field.area(
        "plan-description",
        "Description",
        on(field.help("Optional"), "description"),
        [
          attribute.name("description"),
          attribute.rows(2),
          event.on_input(DescriptionChanged),
        ],
        form.description,
      ),
      athlete_choice(
        "plan-athlete",
        form.athlete_id,
        user_id,
        athletes,
        AthleteChanged,
      ),
      // The start date, the phases and the goal are a group of their own (ADR 0085, 0108).
      layout.subheader("Schedule"),
      field.with_trigger(
        field.native(
          "plan-start",
          "First day",
          on(
            field.help(
              "Weeks run from Monday; moving the plan keeps workouts on their weekday.",
            ),
            "start",
          ),
          [
            attribute.type_("date"),
            attribute.name("start_date"),
            attribute.value(form.start_date),
            attribute.required(form.start_required),
            event.on_input(StartChanged),
          ],
        ),
        date_picker.trigger(start_picker_id, StartPickerOpened),
      ),
      plan_settings.inputs(
        "plan",
        form.settings,
        plan_settings.Messages(
          base_weeks: BaseWeeksChanged,
          pre_competition_weeks: PreCompetitionWeeksChanged,
          competition_weeks: CompetitionWeeksChanged,
          goal_km: GoalChanged,
        ),
        form.error,
      ),
      case form.error, wrong {
        Some(message), "" -> error.message(message)
        _, _ -> element.none()
      },
    ],
  )
}

/// The plan's phases and weekly goal in a line (ADR 0066): "12 weeks: 4 base, 4 pre-competition, 4 competition ·
/// 40.00 km a week". Empty for a plan with neither. They are changed with the plan's Edit.
/// The plan in a line for the app bar's subtitle (ADR 0097): its length, start date and weekly goal.
pub fn subtitle(p: Plan) -> String {
  let weeks = case plan.phase_weeks(p.phases), p.start_date {
    0, Some(start) -> "From " <> date.format(start)
    0, None -> ""
    n, Some(start) -> plural(n, "week") <> " from " <> date.format(start)
    n, None -> plural(n, "week")
  }
  let goal = case p.weekly_distance_m {
    Some(m) if m >. 0.0 -> units.format_planned_km(m) <> " a week"
    _ -> ""
  }
  case weeks, goal {
    "", _ -> goal
    _, "" -> weeks
    _, _ -> weeks <> " · " <> goal
  }
}

/// How the plan's weeks split into phases, under the app bar's subtitle, which has their total.
/// A plan's phases as chip labels in the band titles' words, "Base · 4 weeks"; a phase without weeks has none. The
/// chips are all alike, as the bands are (ADR 0063).
pub fn phase_chips(p: Plan) -> List(String) {
  let phases = p.phases
  [
    #(plan.Base, phases.base_weeks),
    #(plan.PreCompetition, phases.pre_competition_weeks),
    #(plan.Competition, phases.competition_weeks),
  ]
  |> list.filter(fn(phase) { phase.1 > 0 })
  |> list.map(fn(phase) {
    plan.phase_label(phase.0) <> " · " <> plural(phase.1, "week")
  })
}

fn plural(n: Int, word: String) -> String {
  case n {
    1 -> "1 " <> word
    _ -> int.to_string(n) <> " " <> word <> "s"
  }
}

/// The plan list's main action (ADR 0068): a FAB on a phone, a button in the app bar on wider screens.
pub fn main_action(model: Model) -> Option(button.Main(Msg)) {
  case model.mode {
    Creating -> None
    _ -> Some(button.Main(icon.Add, "New plan", NewClicked))
  }
}
