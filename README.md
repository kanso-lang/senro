# senro

A web framework for kanso: routes and models by convention, checked at compile
time, with Postgres and templates that compile to kanso.

## Using it

An app names senro's modules by repository, the way kanso reads any hako
from GitHub:

```
import "kanso-lang/senro/models"
import "kanso-lang/senro/pg"
import "kanso-lang/senro/routes"
import "kanso-lang/senro/web"

derive models/tables
derive routes/rest
```

`kanso install` fetches the repository and writes the lock.
`examples/guestbook` is a whole app. It imports the modules by relative path
because it lives in this repository.

`PRINCIPLES.md` states what senro's design follows.

## What is here

- `routes`: the REST convention, run as a derivation while the app compiles.
  A pub function in one of the app's modules is an action, and its module
  and its name place it: `posts/index` answers GET /posts, `posts/show` GET
  /posts/:id. Any other pub function is refused where it is declared, and
  two routes that can answer the same request are refused at the later one.
  `routes/path_to post` answers a record's show path, through an arm the
  derivation writes into the module that declares the record.
  `routes/path_to "posts/index"` and `routes/path_to "posts/show" 3` name the
  route by its action. A name that is no route, or an id where the route
  takes none, is refused at the call. A module whose member actions (`show`,
  `edit`, `update`, `destroy`) take no `id` is a singular resource:
  `profile/show` answers GET /profile, and the module has no `index`. An app
  that must keep old URLs declares `pub legacy_route_aliases` in one of its
  modules, mapping each old path to the action now answering it, as in
  `{ "GET /signbook":"entries/index" }`. Each alias answers with a 308
  redirect to its action's route, and an alias that names no route, disagrees
  with it about `:id`, or overlaps another route is refused. `web/moved_to`
  answers where a request `web/matched` found is redirected.
- `models`: the schema, folded at compile time from the app's migrations,
  and the check of each model's fields against its table's columns. Each
  model gets a reader in its own module, `signature_from row`, which builds a
  `signature` from a row a query answered, taking each field from the column
  of the same name, or "" when the row has none. As the
  app starts, `models/compared db schema` reads the live tables and answers
  the session when they agree with the schema, or an err naming every column
  whose name, type or nullness differs and every table that is missing.
  Defaults and constraints are not compared. An app whose migrations need SQL
  the fold cannot read, such as a trigger, checks in `pg_dump --schema-only`
  output as `schema.sql` beside its entry, and the schema is read from its
  `CREATE TABLE` blocks instead of the migrations. The dump is loaded with
  psql, which reads the lines Postgres's protocol does not.
- `pg`: a Postgres client written in kanso, speaking the wire protocol over a
  socket, with SCRAM-SHA-256 login and parameterized queries.
  `pg/connect_tls` asks the server for TLS inside the connection, as Postgres
  expects, and checks its certificate against the machine's trusted roots
  (`SSL_CERT_FILE` names others).
- `web`: serves the route table, each connection in a fiber of its own, and
  decodes a posted form. The server opens four database sessions when it
  starts and keeps them in a pool; each request borrows one and gives it back
  when it has answered, and a request that finds all four lent waits. An
  action that fails is answered with a 500, its reason goes to standard
  error, and the server keeps serving. A failure the app expects should be a
  value its action answers. It serves files under the app's `public/`,
  answers `web/redirect`, and keeps a session in a signed cookie
  (`web/session` and `web/kept`). It also serves senro's page script at
  `/senro.js`. A layout that loads it gets pages that update in place: a
  link followed or a form sent on the app's own origin is fetched, and the
  page the server answers is morphed into the live one, so the browser never
  reloads. A field the visitor is typing in keeps what they typed.
- `kata`: `.kata` templates, compiled to kanso functions while the app
  compiles; see `kata/README.md`.

## Specs

```
KANSO=/path/to/kanso sh spec.sh
```

`.kanso-version` pins the compiler CI builds. The specs check every module
and example, compare the guestbook's derived schema and routes with
`spec/guestbook.derived`, compare each view kata writes with the file beside
its template, run each app under `spec/runs` on both engines against its
`.stdout` golden, run each app under `spec/db` the same way against a
Postgres that trusts 127.0.0.1:54329 (`SENRO_NO_DB=1` skips them), and hold each app under `spec/errors` to the refusal its
`.stderr` golden records. `SPEC_WRITE=1` rewrites the goldens.
