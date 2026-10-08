//// The plans screens: the list with a form for new plans, and a single plan with edit and delete.
//// Own state and messages, embedded by the app. Plans are read from the device database; writes
//// are returned as `Action`s for the app to carry out through the sync runner (ADR 0020, 0021).

import atlas/collection
import atlas/outbox
import atlas/plan.{type Plan}
import atlas/plan_form
import atlas/random
import atlas/records
import atlas/route
import atlas/store
import atlas/ui/badge
import atlas/ui/button
import atlas/ui/choice
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
import gleam/dict
import gleam/dynamic.{type Dynamic}
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
    /// The plan page's tab on show (ADR 0058): `"calendar"`, `"schedule"` or `"sharing"`.
    tab: String,
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
  VisibilityChanged(String)
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
  /// A tab of the plan page was chosen (ADR 0058).
  TabSelected(String)
  /// The app made the copy: its plan has this ID.
  CopyMade(String, String)
  CopyFailed(String, String)
  CopyAgainClicked
}

/// A change the user made. The app performs it with the sync runner.
pub type Action {
  Create(id: String, fields: outbox.Fields)
  Edit(id: String, fields: outbox.Fields, base_updated: String)
  Delete(id: String, base_updated: String)
  /// Copy the plan with its workouts into the user's plans. The app builds the records and reports back
  /// with `CopyMade`.
  Copy(source_id: String)
}

pub fn new() -> Model {
  Model([], False, Browsing, plan_form.empty(), undo.new(), NoCopy, "calendar")
}

pub fn refresh() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    store.get_all(collection.Plans, fn(result) { dispatch(PlansRead(result)) })
  })
}

pub fn update(
  model: Model,
  msg: Msg,
  user_id: String,
) -> #(Model, Effect(Msg), List(Action)) {
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
      #(
        Model(..model, plans: plans, loaded: True, mode: mode),
        effect.none(),
        [],
      )
    }
    PlansRead(Error(Nil)) -> #(model, effect.none(), [])

    NewClicked -> #(
      Model(..model, mode: Creating, form: plan_form.empty()),
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
      Model(..model, mode: Browsing, form: plan_form.empty()),
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
    VisibilityChanged(value) ->
      change_form(
        model,
        plan_form.Form(
          ..model.form,
          visibility: plan_form.visibility_from_string(value),
          error: None,
        ),
      )

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
        Ok(valid), Creating -> #(
          Model(..model, mode: Browsing, form: plan_form.empty()),
          effect.none(),
          [Create(random.new_id(), plan_form.create_fields(user_id, valid))],
        )
        Ok(valid), Editing(id) ->
          case find(model.plans, id) {
            Ok(found) if found.owner_id == user_id -> {
              let fields = plan_form.changed_fields(found, valid)
              #(
                Model(..model, mode: Browsing, form: plan_form.empty()),
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

    TabSelected(tab) -> #(Model(..model, tab: tab), effect.none(), [])

    CopyClicked(id) ->
      case model.copy, find(model.plans, id) {
        // One copy at a time, and no second one by a double click.
        Copying(_), _ -> #(model, effect.none(), [])
        Copied(source, _), _ if source == id -> #(model, effect.none(), [])
        _, Ok(_) -> #(Model(..model, copy: Copying(id)), effect.none(), [
          Copy(id),
        ])
        _, Error(Nil) -> #(model, effect.none(), [])
      }

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

pub fn view_list(model: Model, user_id: String) -> Element(Msg) {
  view_list_with(model, user_id, fn(_) { None })
}

/// `shared_by` says who shared a plan with the user, when it was shared with them.
pub fn view_list_with(
  model: Model,
  user_id: String,
  shared_by: fn(Plan) -> Option(String),
) -> Element(Msg) {
  let #(mine, others) =
    model.plans
    |> list.filter(fn(p) { !undo.hides(model.undo, p.id) })
    |> list.partition(fn(p) { p.owner_id == user_id })
  html.section([class("plans")], [
    undo.snackbar(model.undo, "Plan deleted", UndoClicked, DeleteExpired),
    html.div([class("toolbar")], [
      html.h2([], [html.text("Your plans")]),
      case model.mode {
        Creating -> element.none()
        _ ->
          button.fab(
            [attribute.type_("button"), event.on_click(NewClicked)],
            icon.Add,
            "New plan",
          )
      },
    ]),
    form_view(model, model.mode == Creating, "New plan"),
    case model.loaded, mine {
      False, _ -> progress.loading("Loading…")
      True, [] ->
        case model.mode {
          Creating -> element.none()
          _ ->
            empty.view(
              icon.EventNote,
              "You have no plans yet",
              "Create one with New plan, or copy a public plan.",
              None,
            )
        }
      True, plans -> plan_list(plans, shared_by)
    },
    case others {
      [] -> element.none()
      plans ->
        html.div([], [
          html.h2([], [html.text("Shared with you")]),
          plan_list(plans, shared_by),
        ])
    },
  ])
}

pub fn view_detail(model: Model, id: String, user_id: String) -> Element(Msg) {
  view_detail_with(model, id, user_id, fn(_) { None })
}

pub fn view_detail_with(
  model: Model,
  id: String,
  user_id: String,
  shared_by: fn(Plan) -> Option(String),
) -> Element(Msg) {
  case find(model.plans, id) {
    Error(Nil) ->
      html.section([class("plans")], [
        case model.loaded {
          False -> progress.loading("Loading…")
          True ->
            html.p([class("muted")], [
              html.text(
                "This plan is not on this device. It may not have synced yet, or it may have been deleted.",
              ),
            ])
        },
      ])
    Ok(found) -> {
      let mine = found.owner_id == user_id
      html.section([class("plans")], [
        form_view(model, model.mode == Editing(id), "Edit plan"),
        html.div([], [
          badges(found),
          case found.description {
            "" -> element.none()
            text -> html.p([class("description")], [html.text(text)])
          },
          case mine {
            False ->
              html.p([class("muted")], [
                html.text(case shared_by(found) {
                  Some(name) ->
                    "Shared with you by "
                    <> name
                    <> ". Only its owner can change it. Copy it to make a version of your own."
                  None ->
                    "This plan was shared with you. Only its owner can change it. Copy it to make a version of your own."
                }),
              ])
            True -> element.none()
          },
          copy_view(model.copy, found.id),
        ]),
      ])
    }
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
      element.fragment([
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

fn plan_list(
  plans: List(Plan),
  shared_by: fn(Plan) -> Option(String),
) -> Element(Msg) {
  layout.list(
    list.map(plans, fn(p) {
      html.li([], [
        html.a([attribute.href(route.to_path(route.Plan(p.id)))], [
          html.text(p.title),
        ]),
        badges(p),
        case shared_by(p) {
          Some(name) ->
            html.p([class("muted")], [html.text("Shared by " <> name)])
          None -> element.none()
        },
        case p.description {
          "" -> element.none()
          text -> html.p([class("muted")], [html.text(snippet(text))])
        },
      ])
    }),
  )
}

fn badges(p: Plan) -> Element(Msg) {
  html.span([class("badges")], [
    case p.visibility {
      plan.Public -> badge.with_icon(icon.Public, "Public")
      plan.Private -> element.none()
    },
    case p.updated {
      "" -> badge.with_icon(icon.CloudUpload, "Not synced yet")
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

/// Creating and editing a plan happen in a full-screen dialog (ADR 0057).
fn form_view(model: Model, open: Bool, title: String) -> Element(Msg) {
  form_dialog.view(
    "plan-form-dialog",
    open,
    title,
    form_id,
    "Save",
    CancelClicked,
    [form_fields(model.form)],
  )
}

fn form_fields(form: plan_form.Form) -> Element(Msg) {
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
          attribute.rows(4),
          event.on_input(DescriptionChanged),
        ],
        form.description,
      ),
      choice.segmented(
        "visibility",
        "Who can see it",
        plan.visibility_to_string(form.visibility),
        [#("private", "Only me"), #("public", "Everyone")],
        VisibilityChanged,
      ),
      html.p([class("supporting")], [
        html.text(case form.visibility {
          plan.Private -> "You, and the people you share it with."
          plan.Public -> "Everyone who is signed in."
        }),
      ]),
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
