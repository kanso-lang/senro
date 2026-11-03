# Actions that need the server

A component's actions run in the browser today: `more meals` takes the
state and answers the next one, and the page runs it as wasm. Many actions
can't run there. Saving a draft writes to the database, and whether a viewer
may delete a comment depends on who the viewer is. The author still writes
one function, and senro works out the request, the route and the checks.
This note is the plan, and it is deleted when the work has shipped.

## Where an action runs

An action's parameters say where it runs. The state is always the last one.

```
pub fn more meals
  meals + 1

pub fn toggled db s
  next = put s "staple" (not staple? s["staple"])
  pg/query db marked ["{next["staple"]}" "{s["id"]}"] .> (_ -> effect next)
```

`more` takes only the state, so it runs in the browser. `toggled` asks for a
database session, which only the server has; an action may also ask for
`req`, the request, and through it the session cookie. A click bound to
`toggled` posts the component's state to the server. The server runs the
action and answers the next state and the component drawn in it, and the
page morphs that in the same way it morphs a browser action's answer, then
refreshes the rest of itself, since the write may show elsewhere. kata reads
the parameter names, so the placement is never declared separately. A
component with any server action runs all of its actions on the server.

When senro gains sign-in, `viewer` joins `req` and `db` as a parameter an
action may ask for, read from the session.

## What the browser may ask for

A request to `/senro/act/<component>` carries an action's name and a state.
Three rules decide what it can do.

- **Only bound actions are callable.** kata writes each server component's
  `act` from its templates, with an arm for each action a template binds
  with an `on-` attribute, and the app names its server components in the
  route table (`web/components`). A request naming any other action or
  component answers 404. Making a function public does not make it
  reachable from the browser.
- **Only senro's script can ask.** The request must carry the page's
  `senro-page` header. A form on another site cannot set a header, so it
  cannot act with a visitor's cookie.
- **The state is input.** The browser sends the state back, and anyone can
  send any state. It is data in the same sense a form's fields are, so an
  action treats it the way a Rails action treats params, and the policies
  below decide what it may touch.

(The note first planned to sign each state. A view renders without the
app's secret in hand, and signing proves only that the server once produced
a state, which a policy has to check again anyway.)

## Policies

Today the pantry's star toggles whichever item id the state names, so a
crafted request can star any item. That is the gap policies close. A write
passes a policy, written in the model's module as plain functions in
Pundit's shape:

```
pub fn update? viewer item
  item.owner == viewer.id
```

The model's write functions call the policy and answer `forbidden`, a value
that becomes a 403, when it says no. The models derivation refuses to
compile a model that a server action writes when the model has no policy
for that write, so a missing check is a compile error rather than an open
door. Reads follow later as a scope: `pub fn visible viewer` names the rows
a viewer may see, and the model's readers apply it.

## Order of work

1. Server actions: placement by parameters, the closed table, the page
   header. (Built.)
2. Policies on writes, and the refusal of a written model without one.
3. Read scopes.
