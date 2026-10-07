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
import atlas/ui/dialog
import atlas/ui/error
import atlas/ui/field
import atlas/ui/layout
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

const confirm_delete_dialog_id = "confirm-delete-plan"

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
    /// The first click on "Delete" asks; the second one deletes.
    confirming_delete: Bool,
    copy: CopyState,
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
  Submitted
  DeleteClicked
  DeleteConfirmed(String)
  CopyClicked(String)
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
  Model([], False, Browsing, plan_form.empty(), False, NoCopy)
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
      Model(
        ..model,
        mode: Creating,
        form: plan_form.empty(),
        confirming_delete: False,
      ),
      effect.none(),
      [],
    )

    EditClicked(id) ->
      case find(model.plans, id) {
        Ok(found) if found.owner_id == user_id -> #(
          Model(
            ..model,
            mode: Editing(id),
            form: plan_form.from_plan(found),
            confirming_delete: False,
          ),
          effect.none(),
          [],
        )
        _ -> #(model, effect.none(), [])
      }

    CancelClicked -> #(
      Model(
        ..model,
        mode: Browsing,
        form: plan_form.empty(),
        confirming_delete: False,
      ),
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

    DeleteClicked -> #(
      Model(..model, confirming_delete: True),
      dialog.show(confirm_delete_dialog_id),
      [],
    )

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

    DeleteConfirmed(id) ->
      case find(model.plans, id) {
        Ok(found) if found.owner_id == user_id -> #(
          Model(..model, mode: Browsing, confirming_delete: False),
          effect.none(),
          [Delete(id, found.updated)],
        )
        _ -> #(model, effect.none(), [])
      }
  }
}

fn change_form(
  model: Model,
  form: plan_form.Form,
) -> #(Model, Effect(Msg), List(Action)) {
  #(Model(..model, form: form), effect.none(), [])
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
    list.partition(model.plans, fn(p) { p.owner_id == user_id })
  html.section([class("plans")], [
    html.div([class("toolbar")], [
      html.h2([], [html.text("Your plans")]),
      case model.mode {
        Creating -> element.none()
        _ ->
          button.primary(
            [attribute.type_("button"), event.on_click(NewClicked)],
            [html.text("New plan")],
          )
      },
    ]),
    case model.mode {
      Creating -> form_view(model.form, "Create plan")
      _ -> element.none()
    },
    case model.loaded, mine {
      False, _ -> html.p([class("muted")], [html.text("Loading…")])
      True, [] ->
        case model.mode {
          Creating -> element.none()
          _ ->
            html.p([class("muted")], [
              html.text("You have no plans yet. Create one to get started."),
            ])
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
  let back =
    html.a([attribute.href(route.to_path(route.Plans)), class("back")], [
      html.text("← All plans"),
    ])
  case find(model.plans, id) {
    Error(Nil) ->
      html.section([class("plans")], [
        back,
        case model.loaded {
          False -> html.p([class("muted")], [html.text("Loading…")])
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
        back,
        case model.mode {
          Editing(editing) if editing == id ->
            form_view(model.form, "Save changes")
          _ ->
            html.div([], [
              html.h2([], [html.text(found.title)]),
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
                True -> owner_actions(found)
              },
              copy_view(model.copy, found.id),
            ])
        },
      ])
    }
  }
}

fn copy_view(state: CopyState, plan_id: String) -> Element(Msg) {
  case state {
    Copied(source, new_id) if source == plan_id ->
      html.div([class("copied"), attribute.role("status")], [
        html.text("Copied to your plans. "),
        html.a([attribute.href(route.to_path(route.Plan(new_id)))], [
          html.text("Open your copy"),
        ]),
        html.text(" "),
        button.link(
          [attribute.type_("button"), event.on_click(CopyAgainClicked)],
          [html.text("Copy again")],
        ),
      ])
    CopyProblem(source, message) if source == plan_id ->
      html.div([], [
        error.message(message),
        button.secondary(
          [attribute.type_("button"), event.on_click(CopyAgainClicked)],
          [html.text("Try again")],
        ),
      ])
    Copying(source) if source == plan_id ->
      html.p([class("muted")], [html.text("Copying…")])
    _ ->
      layout.actions([
        button.secondary(
          [attribute.type_("button"), event.on_click(CopyClicked(plan_id))],
          [html.text("Copy to my plans")],
        ),
      ])
  }
}

fn owner_actions(found: Plan) -> Element(Msg) {
  layout.actions([
    button.primary(
      [attribute.type_("button"), event.on_click(EditClicked(found.id))],
      [html.text("Edit")],
    ),
    button.danger([attribute.type_("button"), event.on_click(DeleteClicked)], [
      html.text("Delete"),
    ]),
    dialog.view(confirm_delete_dialog_id, "Delete this plan?", CancelClicked, [
      button.danger(
        [attribute.type_("submit"), event.on_click(DeleteConfirmed(found.id))],
        [html.text("Yes, delete it")],
      ),
      button.primary(
        [attribute.type_("submit"), event.on_click(CancelClicked)],
        [html.text("Keep it")],
      ),
    ]),
  ])
}

fn plan_list(
  plans: List(Plan),
  shared_by: fn(Plan) -> Option(String),
) -> Element(Msg) {
  layout.cards(
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
      plan.Public -> badge.badge("Public")
      plan.Private -> element.none()
    },
    case p.updated {
      "" -> badge.badge("Not synced yet")
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

fn form_view(form: plan_form.Form, submit_label: String) -> Element(Msg) {
  html.form([class("plan-form"), event.on_submit(fn(_) { Submitted })], [
    html.label([attribute.for("plan-title")], [html.text("Title")]),
    field.input([
      attribute.id("plan-title"),
      attribute.type_("text"),
      attribute.name("title"),
      attribute.value(form.title),
      attribute.attribute("maxlength", "200"),
      attribute.required(True),
      event.on_input(TitleChanged),
    ]),
    html.label([attribute.for("plan-description")], [html.text("Description")]),
    field.textarea(
      [
        attribute.id("plan-description"),
        attribute.name("description"),
        attribute.rows(4),
        event.on_input(DescriptionChanged),
      ],
      form.description,
    ),
    html.label([attribute.for("plan-visibility")], [html.text("Who can see it")]),
    field.select(
      [
        attribute.id("plan-visibility"),
        attribute.name("visibility"),
        event.on_change(VisibilityChanged),
      ],
      plan.visibility_to_string(form.visibility),
      [
        #("private", "Only me (and people I share it with)"),
        #("public", "Everyone who is signed in"),
      ],
    ),
    case form.error {
      Some(message) -> error.message(message)
      None -> element.none()
    },
    layout.actions([
      button.primary([attribute.type_("submit")], [
        html.text(submit_label),
      ]),
      button.secondary(
        [attribute.type_("button"), event.on_click(CancelClicked)],
        [html.text("Cancel")],
      ),
    ]),
  ])
}
