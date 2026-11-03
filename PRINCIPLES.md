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

## Routes are resources

Every route is RESTful, in the sense DHH argues for at 37signals: an app has
resources, and each action is one of a resource's seven. Singular resources
(`/profile`) and nested resources follow the same rule. There is no way to
declare a route by hand.

An app that must keep an old URL declares it in `legacy_route_aliases`
(kanso#2280), which maps the old path to a RESTful route. The name says what
it is: a compatibility measure. Each alias answers with a permanent redirect
to its route, so every resource keeps one URL, and an alias pointing at no
route is refused like any other mistake.

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

Views are Slim-like templates (kanso#2178), and kata compiles each one to
kanso. A template is checked like any other code: a misspelled field is
refused at the line that reads it.

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

## Every behavior has a spec

Each convention, refusal and runtime behavior has an app under `spec/` and
the output, or the refusal, it must produce. A change to what senro does
changes a spec in the same pull request.
