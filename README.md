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
`examples/guestbook` and `examples/pantry` are whole apps. They import the
modules by relative path because they live in this repository. The pantry
adds, counts, renames and removes things on a shelf without a page reload.

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
  takes none, is refused at the call. A module whose name ends in
  `_mailer` makes the app's mail, as a Rails mailer does: its pub functions
  are called by actions in other modules, and none of them is a route. A
  module whose member actions (`show`, `edit`, `update`, `destroy`) take no
  `id` is a singular resource:
  `profile/show` answers GET /profile, and the module has no `index`. An app
  that must keep old URLs declares `pub legacy_route_aliases` in one of its
  modules, mapping each old path to the action now answering it, as in
  `{ "GET /signbook":"entries/index" }`. Each alias answers with a 308
  redirect to its action's route, and an alias that names no route, disagrees
  with it about `:id`, or overlaps another route is refused. `web/moved_to`
  answers where a request `web/matched` found is redirected. A module that
  lets one client call an action only so often declares `pub rate_limits`,
  as in `{ "create":"10 per 3 minutes" }`. The server counts each client's
  calls by its address, in memory, and answers a call past the limit with
  429 Too Many Requests before it reaches the action, or with what the
  module's `over_limit req` answers when it writes one. Once it holds more
  than `web/sweep_past` clients it forgets those whose calls have all aged
  out, and `web/remembered` says how many it holds. A limit on no action
  of its module, or one that does not read as a count per a window, is
  refused at the declaration. `web/peer req` answers the client's address.
  An app that wraps its table in `web/requiring_sign_in routes secret` asks
  every action for a visitor who has signed in, except those its module
  lists in `pub without_sign_in`, as Rails 8's generated authentication
  does. A visitor who has not is sent to `/session/new`, the path a GET
  asked for is kept in the session, and `web/return_to req secret fallback`
  answers it once the visitor has signed in.
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
  A model's module may also declare policies, `update?` and `destroy?`,
  each taking the viewer and the row. The derivation describes each model
  with an `id` as a value (`signature_model`), and `models/updated` and
  `models/destroyed` take it, read the row, ask the policy and write only on
  a yes, answering `web/denied` or `web/absent` otherwise. A model with no
  such policy cannot be written this way. A model's module may declare
  `visible?` too, and `models/shown viewer model rows` keeps the records a
  query answered that the viewer may see. Without a `visible?` every row
  shows: a missing read policy can show a row but never change one, so reads
  default open where writes default closed. A record is made with
  `models/created viewer db model fields`, which reads the fields (a
  posted form, say) into a record, asks the `create?` policy, checks the
  module's `problems`, and inserts only when both pass; `models/updated`
  checks `problems` too, on the record as the change leaves it.
  `problems` takes the record and answers `models/problems` of a list of
  `models/rule field broken message`. A record that breaks a rule comes
  back as `models/invalid`, holding each broken field's message and the
  record as given, so the action can show the form again with both.
- `pg`: a Postgres client written in kanso, speaking the wire protocol over a
  socket, with SCRAM-SHA-256 login and parameterized queries.
  `pg/connect_tls` asks the server for TLS inside the connection, as Postgres
  expects, and checks its certificate against the machine's trusted roots
  (`SSL_CERT_FILE` names others).
- `web`: serves the route table, each connection in a fiber of its own, and
  decodes a posted form. The server opens a pool of database sessions when it
  starts (`sessions` in `web.kso`); each request borrows one and gives it back
  when it has answered, and a request that finds them all lent waits. An action
  that fails is answered with a 500, its reason goes to standard error, and the
  server keeps serving. A failure the app expects should be a value its action
  answers. It serves files under the app's `public/`, answers `web/redirect`,
  and keeps a session in a signed cookie (`web/session` and `web/kept`). The
  server stamps each request with the time it arrived, and a sign-in
  (`web/signed_in`) lasts `web/session_days`, fourteen, from the request that
  made it; after that the session reads without its viewer. The cookie lasts
  until the browser closes, and `web/lasting` keeps it for those fourteen days
  instead, as Devise's "remember me" does; the guestbook's sign-in form offers
  it. It also serves senro's page script at `/senro.js`. A layout that loads it
  gets pages that update in place: a link followed or a form sent on the app's
  own origin is fetched, and the page the server answers is morphed into the
  live one, so the browser never reloads. Once the app's browser module has
  loaded, a page the app answers with `views/answer` arrives as data and is
  rendered in the browser. The script keeps the app's module and the runtime in
  the browser's Cache Storage, each under its modification time, which the
  server writes into `/senro.js`, so a returning visitor compiles them without
  asking for them. Every answer to the script names that version, and a page
  opened before a deploy that changed it loads itself again, once. A field the
  visitor is typing in keeps what they typed, unless it was in the form just
  sent. A form that POSTs a `_method` of `PATCH` or `DELETE` is routed as that
  method, as in Rails. When a request that isn't a GET finishes, the server
  notifies Postgres's `senro` channel, and every page holding `/senro/live` open
  fetches itself again, so one visitor's change shows on another's page.
- `passwords`: passwords kept as PBKDF2-SHA-256 digests under a salt from
  the operating system's secure source (`os/random_bytes`).
  `passwords/digested password` describes the stored text, which names its
  rounds, salt and digest; `passwords/matches? password kept` checks a
  password against it, comparing every byte. A sign-in for a name with no
  account checks against `passwords/stand_in`, which costs the same, so a
  refusal's timing does not say whether the name exists. The rounds are
  `SENRO_PASSWORD_ROUNDS`, or 100,000 when it is unset; the comment above
  `default_rounds` says why that is below OWASP's figure. The specs set 30.
  `passwords/reset_token secret id kept t` makes the token a password reset
  link carries: a `tokens` token bound to the digest the account keeps, so
  a new password retires it, good for fifteen minutes. `passwords/reset_id`
  reads the id to look the digest up by, and `passwords/reset_valid?` checks
  the token against it.
- `tokens`: signed tokens for links an app mails out, as Rails 8's
  `generates_token_for` makes them. `tokens/made purpose secret id bound t
  minutes` names a record, an expiry, and an HMAC over both, the purpose and
  a value the record holds now. Nothing is stored: when the bound value
  changes, the tokens made over the old one stop working, and a token made
  for one purpose opens nothing else. `tokens/id_of` reads the record's id,
  and `tokens/valid? purpose secret token bound t` checks the rest.
- `mail`: mail an app sends, such as a password reset. `mail/composed from
  to subject body` makes a plain-text message, and `mail/delivered m` sends
  it the way `SENRO_MAIL` names: to standard error when it is unset, as
  development wants; to a file of its own under a directory (`dir:<path>`);
  or over SMTP (`smtp://user:pass@host:587`, `smtps://` for TLS from the
  first byte). `smtp://` sends only after STARTTLS and refuses a server that
  does not offer it; `smtp+insecure://` is for a mail catcher on the
  developer's own machine. `mail/url_for path` is the link a mail carries:
  `SENRO_URL`, or `http://127.0.0.1:3000` when it is unset, then the path,
  and never the request's Host header. A header holding a line break, or an
  address with no `@`, is refused before anything is sent. A subject that is not
  ASCII travels as RFC 2047 encoded words, and a body that is not ASCII, or
  holds a line longer than SMTP allows, as base64.
- `browser`: what an app's components and pages need in the browser.
  `browser.kso` beside the app's entry names its browser components with
  `browser/answer`, or with `browser/answer_pages` when the module renders
  the app's pages too (see `kata/README.md`). `sh browser/build.sh <app>
  <runtime.wasm>` builds it for the browser into the app's `public/senro/`,
  beside kanso's runtime for wasm32 (`scripts/build_runtime_wasm.sh` in
  kanso). Until the module has loaded, an element marked
  `data-while-loading` shows and one marked `data-when-loaded` is hidden;
  afterwards it is the other way round. senro shows nothing of its own
  while loading.
- `kata`: `.kata` templates, compiled to kanso functions while the app
  compiles; see `kata/README.md`.

## Specs

```
KANSO=/path/to/kanso sh spec.sh
```

`.kanso-version` pins the compiler CI builds. The comment at the top of
`spec.sh` lists what the specs check. `SENRO_NO_DB=1` skips those that need
Postgres, `KANSO_RUNTIME_WASM` names the runtime the browser specs load,
and `SPEC_WRITE=1` rewrites the goldens.
