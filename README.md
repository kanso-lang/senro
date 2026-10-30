# senro

A web framework for kanso: routes and models by convention, checked at compile
time, with Postgres and Slim-style templates.

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
  takes none, is refused at the call.
- `models`: the schema, folded at compile time from the app's migrations,
  and the check of each model's fields against its table's columns.
- `pg`: a Postgres client written in kanso, speaking the wire protocol over a
  socket, with SCRAM-SHA-256 login and parameterized queries.
- `web`: serves the route table and decodes a posted form.
- `kata`: Slim-style templates compiled to kanso functions. `bin/kata` is its
  command line; see `kata/README.md`.

## Specs

```
KANSO=/path/to/kanso sh spec.sh
```

`.kanso-version` pins the compiler CI builds. The specs check every module
and example, compare the guestbook's derived schema and routes with
`spec/guestbook.derived`, compare each view kata writes with the file beside
its template, run each app under `spec/runs` on both engines against its
`.stdout` golden, and hold each app under `spec/errors` to the refusal its
`.stderr` golden records. `SPEC_WRITE=1` rewrites the goldens.
