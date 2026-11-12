# What senro believes

senro is a web framework for kanso in the tradition of Rails. It aims for the
same economy: a small app is a few short files, and the framework supplies
everything the files leave unsaid. Where Rails decides at run time, senro
decides while the app compiles, so a mistake that Rails reports on a request
is a compile error here.

This page states the principles behind senro's design. Each one comes from a
ruling on the kanso tracker, named after it, or from the language itself. A
design decision that none of them settles is made to fit them, and the page
grows when a new one is needed.

## The source holds decisions, and conventions supply the rest

kanso's premise is a language whose source contains only decisions. senro
applies it to the web: an app writes what is particular to it, and a
convention places everything else. An action named `entries/index` answers
GET /entries because of its name, a model reads its table because of its
name, and a migration is the schema because nothing else needs to be.

A convention is a derivation (kanso#2186): a kanso function the framework
ships, which the compiler runs during the build. What it produces is checked
like hand-written code, and `kanso derived` prints it, so nothing a
convention does is hidden.

## What a convention cannot place is refused

A public function that no route can answer is a compile error where it is
declared. The same goes for two routes that could answer the same request, a
`path_to` that names no route, a model field with no column, and a template
that reads a field its record lacks. senro would rather stop the build than
leave a dead route or a page that fails on its first request.

## One way to do each thing

An app does each thing one way, and senro offers only that way
(kanso#2468). A link or a redirect names its route with `path_to`, the
route's name written as a string and an id for each id the route has. A
link mailed to a visitor is signed by `tokens/made`, for a purpose. An
entry starts its app with `app/run`. Where two spellings did the same work,
one was kept and the other cut. A public name stays public while an app or
one of senro's specs calls it, and a setting nobody would choose
differently is fixed instead of offered.

What senro can find, it finds by name, so an app never passes it along. A
module's `rate_limits` and `without_sign_in` are read where they are
declared, and so is the session module's `secret`, which `SENRO_SECRET`
replaces in a deployed app. The request carries that secret to everything
that signs, so no call takes it as an argument. A component's action that
takes a parameter named `req`, `db` or `viewer` runs on the server and is
handed it.

## Routes are resources

Every route is RESTful, in the sense DHH argues for at 37signals: an app has
resources, and each action is one of a resource's seven. Singular resources
(`/profile`) and nested resources follow the same rule. There is no way to
declare a route by hand.

An app that must keep an old URL declares it in `legacy_route_aliases`
(kanso#2280), a list of calls such as `(routes/moved "/signbook"
entries/index)`, each naming an old path and the RESTful action that answers
it now. The action is written as code, so the compiler checks it, and the
alias takes its method from the action's route, so there is no method to get
wrong. The name says what it is: a compatibility measure. Each alias answers
with a permanent redirect to its route, so every resource keeps one URL, and
an alias pointing at no route is refused like any other mistake.

## The schema comes from the migrations

There is no schema file (kanso#2186). A kanso migration is a value built from
a fixed set of changes, so it cannot break when a model changes later, and
the schema is folded from the migrations while the app compiles. An app whose
migrations need SQL the fold cannot read checks in a `schema.sql` instead.
When the app starts, senro compares the live tables with that schema and
refuses to serve if they differ.

## Postgres, spoken in kanso

senro speaks to Postgres over the wire protocol, in a client written in kanso
(kanso#2178). There is no C binding and no second database to abstract over.

## Templates compile

Views are `.kata` templates, and kata compiles each one to a kanso function
while the app compiles (kanso#2178, kanso#2280). A template is a file of its
own, with no generated source beside it, and it is checked like any other
code: a misspelled field is refused at the line that reads it.

## Expected outcomes are values

A failure an app expects is a value its action answers, never an err raised
for control flow (kanso#2087, kanso#2252). An HTTP status is part of a
response, never an exception (kanso#2253). senro's server rescues an
action's unexpected failure, answers 500, reports it, and keeps serving.

## One program on every engine

An app answers the same bytes on kanso's interpreter and natively, and
senro's specs run both. Requests run as fibers that the scheduler orders
deterministically, so a program's interleaving is the same on every run.
Shared state, such as a pool of database sessions, uses kanso's own
structures (kanso#2264).

## A view renders wherever it is needed

The goal is an app that feels as quick as a single-page application while its
author writes ordinary server code: actions that read the database and hand
records to views. kanso compiles to WASM as well as natively, and its engines
answer the same bytes for the same program, so a kata view can run in the
browser and produce exactly what the server would have.

A page's first request answers HTML, rendered on the server, so it shows at
once and works without a script. The browser then loads the app's views as
WASM. After that a link or a form asks the server only for the data its views
need, in a compact encoding, and the browser renders the
views itself and morphs the page in place. The app's author never writes
client code, and the two renderings cannot drift apart, because they are the
same program. Firefox is the first browser this is tuned for.

The guestbook's pages work this way (`kata/README.md`). `spec/runs/pages`
holds a page rendered from its data on the server, in the browser module on
every engine, and by its template from the records, to the same bytes.

## Every behavior has a spec

Each convention, refusal and runtime behavior has an app under `spec/` and
the output, or the refusal, it must produce. A change to what senro does
changes a spec in the same pull request.
