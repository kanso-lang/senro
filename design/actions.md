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

**The viewer.** An app signs a visitor in by keeping their id in the session
(`web/signed_in r secret held id`), and `web/components` takes the app's
secret so the server can read it back (`web/viewer`). An action that asks for
`viewer` is handed that id, or "" for a visitor who has not signed in.
Nothing in the request body can name a viewer.

**A policy is a function in the model's module**, in Pundit's shape, named
for the write it allows:

```
pub fn destroy? viewer s
  s.name == viewer
```

**Writes go through the model.** The models derivation writes, for each
model with an `id`, a value describing it: `signature_model`, a map of its
table, its columns, its reader and each policy its module declares.
`models/destroyed viewer db signatures/signature_model id` reads the row,
asks `destroy?`, and deletes it only when the policy says yes;
`models/updated viewer db model id changes` does the same with `update?`.
A no answers `web/denied` and a missing row `web/absent`, which the server
answers as 403 and 404. A model whose module declares no `destroy?` cannot
be destroyed this way, so leaving a policy out denies the write. An app that
means anyone may write says so (`pub fn update? _ _` answering true, as the
pantry does).

The derived code stays pure: a derived file cannot import senro's `pg` or
`web`, because the derivation cannot know the path the app imports them by.
The writes live in `models`, which can.

**A server action may not write around its model.** kata refuses a server
action that calls `pg/query` or `pg/run` itself, at the call. The check reads
the action's own calls, so a helper could still hide one; the convention and
the refusal together make the checked path the easy one.

Reads follow the same pattern later: `pub fn visible? viewer entry` decides
what a viewer may see, and the model's readers drop the rest.

## Order of work

1. Server actions: placement by parameters, the closed table, the page
   header. (Built.)
2. The viewer, policies, the model's checked writes, and the refusal of a
   server action that writes around its model. The guestbook signs a
   visitor in under the name they sign with, and only an entry's author can
   remove it. (Built.)
3. Read policies.
