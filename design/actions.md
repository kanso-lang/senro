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

pub fn save viewer db draft
  items/rename viewer db draft.id draft.name .> (_ -> draft)
```

`more` takes only the state, so it runs in the browser. `save` asks for the
viewer and a database session, which only the server has. A click bound to
`save` posts the component's state to the server. The server runs `save` and
answers the next state and the component drawn in it, and the page morphs
that in the same way it morphs a browser action's answer. The derivation
reads the parameter names, so the placement is never declared separately.

A component with any server action runs all of its actions on the server.
Its state then changes only on the server, which is what makes signing it
(below) sound.

## What the browser may ask for

A request to `/senro/act` names a component, an action and a state. Three
rules decide what it can do.

- **Only bound actions are callable.** The derivation writes the server's
  action table from the templates: an action is in it when a template binds
  it with an `on-` attribute. A request naming anything else answers 404.
  Making a function public does not make it reachable from the browser.
- **The viewer comes from the session.** `viewer` is read from the signed
  session cookie on every request. Nothing in the request body can name a
  viewer.
- **State is signed.** The server signs every state it renders or answers
  for a component with server actions, using the app's secret and
  `std/hmac`. A server action runs only on a state whose signature checks,
  so the browser cannot hand it a state the server never produced, such as
  another visitor's item id.

## Policies

A valid signature proves the server produced the state. It does not prove
the viewer may still act on it: a session changes hands, a row changes
owner. So a write also passes a policy, written in the model's module as
plain functions in Pundit's shape:

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

1. Server actions: placement by parameters, the closed table, the viewer
   from the session, signed state.
2. Policies on writes, and the refusal of a written model without one.
3. Read scopes.
