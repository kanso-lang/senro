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

## Generating an app

senro's generators write an app and its resources, as Rails' do. They run
from senro's own directory, and take the app's path relative to it:

```
kanso run generate -- new apps/notebook
kanso run generate -- scaffold apps/notebook note title:text pages:int cover:attachment
kanso run generate -- scaffold apps/notebook page body:text note:references
kanso run generate -- authentication apps/notebook
```

`new` writes an entry, a home page, a layout and a migrations module with no
changes in it. The entry connects to the Postgres that `PGHOST`, `PGPORT`,
`PGUSER`, `PGDATABASE` and `PGPASSWORD` name, runs the app's migrations, and
serves on port 3000.

`scaffold` takes a singular name and its fields, each `name:text`,
`name:int`, `name:references` or `name:attachment`, and `:uniq` after the
kind gives the column a unique index, as Rails' generator reads it
(`email:text:uniq`). A field's name is a lowercase letter and
then letters, digits and underscores, at most 24 in all; a resource's name
is spelled the same way, at most 16. It writes a module whose seven actions
list, show, make, change and remove rows through the model, and the three views
they render. The list shows 25 rows a page (`per_page` in the module), read
with `models/paged`, and links the pages before and after it as
`?page=2`. The list and the page for one row answer JSON when it is asked
for, as a Rails scaffold's do: `/notes.json` is the page's rows, each as
`note_attributes` gives it, and `/notes/3.json` is one. Each `int` field
gets a rule that the value is a whole number, so a form that says otherwise
is shown again with the problem rather than
refused by Postgres. It adds the migration that makes the table, whose last
columns are `models/created_at` and `models/updated_at`, to the end of
`migrations/all`, and the module's import to the entry. The policies it
writes let anyone write; narrow them before the app is public.

A `references` field nests the resource under another, as Rails' generator
reads it. `page body:text note:references` gives each page a `note_id`
column and a foreign key to `notes` that removes a note's pages with it
(`models/add_foreign_key`). Its actions take the note's id and answer under
/notes/:note_id/pages, and a page is found only under its own note. The
note's resource must be there already, a resource names one parent, and a
reference's name is at most 12 characters.

An `attachment` field is a file, kept as an upload is (see the web module
below) and stored as its key, as Active Storage's `has_one_attached` keeps
one. `cover:attachment` gives the note a `cover` column, a file input in a
form sent as multipart, and a link to the file on the note's page. Changing
the note without choosing a file keeps the one it has.

`authentication` adds accounts, as Rails 8's authentication generator does,
with a sign-up page as Devise's registerable adds. It writes a `users` table
of addresses, each held by one account, and password digests,
`registration` (/registration/new),
`session` (signing in at /session/new and out with DELETE /session) and
`resets` (a lost password, by a link mailed through `password_mailer`),
with their views. The entry then serves every route behind
`web/requiring_sign_in`, so an action asks for a sign-in unless its module
lists it in `without_sign_in`, and runs a mail worker beside the server
(`jobs/beside`). `session.kso` holds the secret that signs sessions, 32
random bytes made when the generator ran; keep it out of a public
repository. The files are copied from `generate/authentication`, which
holds them as an app two directories below senro would.

Each generator prints the files it writes and changes. A file that is there
already stops it before it writes anything, and so does a name or field it
cannot read. `examples/notebook` is the app the four commands above write
when they are given that path. The specs write it again and compare the two.

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
  `profile/show` answers GET /profile, and the module has no `index`. A
  module whose actions each take a parent's id first is nested under the
  parent: `comments/index req db post_id` answers GET
  /posts/:post_id/comments and `comments/show req db post_id id` GET
  /posts/:post_id/comments/:id. Nesting goes one level deep, and an action
  of a nested module that takes no `post_id`, or takes it after `id`, is
  refused. `routes/path_to "comments/show" 3 4` names a nested route with
  the parent's id first, and `path_to comment` reads it from the record's
  own `post_id`. An app
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
  An app that wraps its table in `web/requiring_sign_in routes secret
  bound_of` asks every action for a visitor who has signed in, except those
  its module lists in `pub without_sign_in`, as Rails 8's generated
  authentication does. A visitor who has not is sent to `/session/new`, the
  path a GET asked for is kept in the session, and `web/return_to req
  secret fallback` answers it once the visitor has signed in. A sign-in
  rests on something the account holds, which `web/signed_in` is given and
  keeps an HMAC of in the session; the guestbook's is the password's
  digest. `bound_of db id` reads it at every action, open or not, and a
  sign-in that rested on something else is over, so a new password ends
  every older sign-in, as Devise's does. An action that asks for a sign-in
  sends that visitor to sign in again; an open one runs as if nobody had
  signed in, and its answer tells the browser to forget the sign-in.
  Components' actions are open, since their models' policies decide, so
  the table goes through `web/components` first and then through
  `web/requiring_sign_in`. An app whose sign-ins rest on nothing passes
  `web/unbound` and "".
- `models`: the schema, folded at compile time from the app's migrations,
  and the check of each model's fields against its table's columns. Each
  model gets a reader in its own module, `signature_from row`, which builds a
  `signature` from a row a query answered, taking each field from the column
  of the same name, or "" when the row has none. It gets
  `signature_attributes s` too, the record as a map from each field's name to
  its value, as Rails' `attributes` gives one, which `web/json` writes as an
  object; a module that declares the function keeps its own. A table made with
  `models/timestamps` among its columns, or `models/created_at` and
  `models/updated_at` one at a time, has `created_at` and `updated_at`, as
  Rails' `t.timestamps` gives: Postgres sets both when a row is made,
  `models/updated` sets `updated_at` on every change, and a form's value for
  either is ignored. As the app starts,
  `models/migrated db app migrations/all` runs the migrations the database has
  not yet run, in order, and records each in `senro_migrations` under the app's
  name and its place in the list, beside the SQL it ran, as Rails records them
  in `schema_migrations`; two apps can share a database. A migration runs once;
  one whose SQL has changed since it ran stops the app, naming it, so a new
  change goes at the end of the list. Each change does nothing when its work is
  already done, so a database made before migrations were recorded takes the
  list safely the first time. Then `models/compared db schema` reads the live
  tables and answers the session when they agree with the schema, or an err
  naming every column whose name, type or nullness differs and every table that
  is missing. Defaults and constraints are not compared, so a key added with
  `models/add_foreign_key table column parent` leaves the schema as it was; it
  makes the column hold a row of `parent` and removes the row with its parent,
  as Rails' `add_foreign_key` with `on_delete: :cascade` does.
  `models/add_unique_index table column` gives the column a unique index, as
  Rails' `add_index` with `unique: true` does. The model then names the
  column as unique, and `models/created` inserts with `on conflict do
  nothing`, so of two requests racing for one value the one that loses
  answers `invalid` with "That is taken." on the field rather than an error.
  `models/updated` asks before it writes, and a change that races another
  for the value meets the index. A column whose kind says `unique`, and a
  unique index or constraint over one column in `schema.sql`, count the same
  way. An app whose
  migrations need SQL the fold cannot read, such as a trigger, checks in
  `pg_dump --schema-only` output as `schema.sql` beside its entry, and the
  schema is read from its `CREATE TABLE` blocks instead of the migrations.
  The dump is loaded with psql, which reads the lines Postgres's protocol does
  not.
  A model's module may also declare policies, `update?` and `destroy?`,
  each taking the viewer and the row. The derivation describes each model
  with an `id` as a value (`signature_model`), and `models/updated` and
  `models/destroyed` take it, read the row, ask the policy and write only on
  a yes, answering `web/denied` or `web/absent` otherwise. A model with no
  such policy cannot be written this way.

  An action reads and writes through its models by name and writes no SQL.
  The `db` senro hands an action already knows who is signed in: the web
  layer names the viewer on the session (`pg/asked_by`) before an action, a
  server component or a provider sees it, and a session nobody named asks
  as a visitor. A module that holds one model answers for it, as a Rails
  model answers its class methods:

  | call | answers |
  |---|---|
  | `notes/find db id` | the record, or none |
  | `notes/find_by db "title" t` | the first record whose field holds the value, or none |
  | `notes/all db` | every record, oldest first |
  | `notes/newest db` | every record, the one made last first |
  | `notes/ordered db "title"` | every record in the order of a column |
  | `notes/where db "title" t` | the records whose field holds the value |
  | `notes/paged db number per` | one page of the records, oldest first |
  | `notes/create db fields` | the record as stored, or `models/invalid` |
  | `notes/update db id changes` | the record as changed, or `models/invalid` |
  | `notes/destroy db id` | the record as it was |

  A read shows only what the viewer's read policy allows. A write asks the
  model's `create?`, `update?` or `destroy?` about the same viewer and
  answers `web/denied` on a no, and `update` and `destroy` answer
  `web/absent` for an id no row has. A field or an order written out in
  the call is checked against the table's columns when the app is checked
  (`spec/errors/order_not_a_column`), and one that arrives in a variable
  is checked before any SQL is sent (`spec/db/asked`,
  `examples/pantry/items.kso`). A module that declares a function of one
  of these names keeps its own, and a module with two models gets none,
  since a bare `find` would not say which.

  Underneath, `models/found viewer db model id`
  reads a record by its id, or answers none when there is no such row or
  the viewer may not see it, and `models/where viewer db model field value`
  answers the records whose field holds the value, oldest first, that the
  viewer may see: a post's comments are `models/where viewer db
  comment/comment_model "post_id" id`. A foreign key the migrations add
  writes that call for the app, once in each direction, as Rails'
  `has_many` and `belongs_to` do. `pages.note_id` holding a row of `notes`
  gives `pages/of_note viewer db note`, the pages of a note the viewer may
  see, and `notes/of_page viewer db page`, the note a page belongs to. Each
  reads the other record's field by name, so neither module imports the
  other. A module that declares a function of the same name keeps its own,
  as does one that declares a pub function or record named as the parameter
  (`note`, `page`). A schema read from `schema.sql` takes its keys from the
  dump's `FOREIGN KEY ... REFERENCES` constraints. `models/paged db sql params number
  per` reads one page of a query, as Pagy does: its rows, its number, and
  whether another follows, which it learns by asking for one row more than
  the page shows. `models/page_number` reads the page a query string names,
  so `/notes?page=2` is `models/page_number (web/value (web/query req)
  "page")`, and anything but a whole number of at least 1 is page 1. A field
  written out is checked
  against the model's columns while the app compiles. A model's column names are a
  constant of its module, `signature_columns`, which the model value and the
  module's own SQL both read, so a column a migration adds reaches every
  query with no edit. A model's module may declare
  `visible?` too, and `models/shown viewer model rows` keeps the records a
  query answered that the viewer may see. Without a `visible?` every row
  shows: a missing read policy can show a row but never change one, so reads
  default open where writes default closed. A record is made with
  `models/created viewer db model fields`, which reads the fields (a
  posted form, say) into a record, asks the `create?` policy, checks the
  module's `problems`, and inserts only when both pass; `models/updated`
  checks `problems` too, on the record as the change leaves it.
  `problems` takes the record and answers `models/problems` of a list of
  `models/rule field broken message`. `models/whole_number field value` is
  the rule that a value is one an `integer` column takes, which
  `models/integer? value` answers: digits with or without a sign, inside the
  column's range. `models/present field value` is the rule that a value is
  filled in, as Rails' `presence: true` reads one, and spaces alone are
  blank; `models/at_most field n value` and `models/at_least field n value`
  bound its length in characters, as `length: { maximum:, minimum: }` does.
  `models/one_of field choices value` is the rule that a value is one of a
  list, as `inclusion: { in: }` reads one, compared whole.
  `models/email_address field value` is the rule that a value is shaped like
  an email address: one @, something on each side of it, and no spaces.
  A record that breaks a rule comes back as
  `models/invalid`, holding each broken field's message and the record as
  given, so the action can show the form again with both.
- `pg`: a Postgres client written in kanso, speaking the wire protocol over a
  socket, with SCRAM-SHA-256 login and parameterized queries.
  `pg/connect_tls` asks the server for TLS inside the connection, as Postgres
  expects, and checks its certificate against the machine's trusted roots
  (`SSL_CERT_FILE` names others). `pg/from_env` connects as libpq would,
  from `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` and `PGPASSWORD`, with
  libpq's defaults for any that are unset.
- `web`: serves the route table, each connection in a fiber of its own, and
  decodes a posted form. A path's query string is taken off before the route
  is matched, so `/notes?page=2` answers as `/notes` does, and `web/query req`
  reads it as a form: `web/value (web/query req) "page"` is "2". A request is
  read as bytes until its body is as long
  as its `Content-Length` says, since a browser often sends the head and the
  body in separate packets. A body over 10 MiB is refused with a 413 before it
  is read, and a client that sends `Expect: 100-continue`, as curl does before
  a large upload, is told to go on. A form sent as `multipart/form-data`, which is how a browser sends a
  file, reaches its action as any other form does: each file is written to
  `storage/` beside the app (or the directory `SENRO_STORAGE` names) under a
  key of 32 random hex digits, and the form holds the key where the file was,
  as Active Storage's disk service keeps a blob. The action stores the key in
  a column, and a view links it with `web/blob_path key`, which serves the
  file at `/senro/blobs/<key>`. An image or a PDF is shown in the page; any
  other kind is sent as a download, so an HTML file someone uploaded never runs
  as a page of the app. A file input left empty reads as "". The server opens a pool of database sessions when it
  starts (`sessions` in `web.kso`); each request borrows one and gives it back
  when it has answered, and a request that finds them all lent waits. An action
  that fails is answered with a 500, its reason goes to standard error, and the
  server keeps serving. A request that would change something (any method but
  GET and HEAD) is refused with a 403 when a browser says another site sent it:
  `Sec-Fetch-Site` anything but `same-origin` or `none`, or, from a browser too
  old for that header, an `Origin` other than the app's own. The session cookie
  is SameSite=Lax, so a browser should not carry it on such a request anyway;
  this is the check Rails' `protect_from_forgery` makes. A request with neither
  header comes from a program, and is let through. Every answer carries the
  headers Rails sends by default: `x-frame-options: SAMEORIGIN`, so another
  site cannot show a page in a frame; `x-content-type-options: nosniff`;
  `referrer-policy: strict-origin-when-cross-origin`;
  `x-permitted-cross-domain-policies: none`; and `x-xss-protection: 0`. An
  answer that sets one of them itself keeps its own (`spec/serve/guarded`).
  A failure the app expects
  should be a value its action answers. It serves files under the app's
  `public/`, answers `web/redirect`, and answers `web/json status value`,
  as Rails' `render json:` does, for a request that asks for JSON
  (`web/wants_json? req`): one whose path ends `.json`, matched as the path
  without it, or whose Accept header names `application/json`. It keeps a
  session in a signed cookie
  (`web/session` and `web/kept`). An answer that would set the session the
  request already carries sets none, so a page answered from a session read
  before a sign-out cannot put the sign-in back. The server stamps each
  request with the time
  it arrived, and a sign-in (`web/signed_in`) lasts `web/session_days`,
  fourteen, from the request that made it; after that the session reads without
  its viewer. The cookie lasts until the browser closes, and a session made
  `web/lasting` keeps it for those fourteen days instead, through every later
  write, as Devise's "remember me" does; the guestbook's sign-in form offers
  it. `web/signed_out` forgets the sign-in and keeps the rest. An answer can
  leave a notice for the next page, as Rails' flash does:
  `web/noticed (web/redirect "/") "Thank you for signing."` sends the browser
  on with one, the page it lands on reads it with `web/notice req`, and the
  server forgets it once that page is answered. A notice has a cookie of its
  own, so forgetting one never sets the session. It also serves
  senro's page script at `/senro.js`. A layout that loads it gets pages that
  update in place: a link followed or a form sent on the app's own origin is
  fetched, and the page the server answers is morphed into the live one, so the
  browser never reloads. A form whose `enctype` is `multipart/form-data` is
  sent that way, with its files; any other is sent urlencoded. Once the app's browser module has loaded, a page the
  app answers with `views/answer` arrives as data and is rendered in the
  browser. The script keeps the app's module and the runtime in the browser's
  Cache Storage, each under its modification time, which the server writes into
  `/senro.js`, so a returning visitor compiles them without asking for them.
  Every answer to the script names that version, and a page opened before a
  deploy that changed it loads itself again, once. A field the visitor is typing
  in keeps what they typed, unless it was in the form just sent. A form that
  POSTs a `_method` of `PATCH` or `DELETE` is routed as that method, as in
  Rails. When a request that isn't a GET finishes, the server notifies
  Postgres's `senro` channel, and every page holding `/senro/live` open fetches
  itself again, so one visitor's change shows on another's page.
  `web/refusal` answers a `web/denied` with 403 Forbidden and a `web/absent`
  with 404 Not Found.
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
  `mail/delivered_later db m` queues the message as a job on the `mail`
  queue instead, as Action Mailer's `deliver_later` does, and a worker
  running `mail/performers` sends it. A message `delivered` would refuse is
  refused before it is queued.
- `jobs`: work an app does after the request that asked for it, as Active
  Job does it on Solid Queue. Each job is a row of `senro_jobs`, which
  `jobs/prepared db` makes when it is missing, so a job outlives the process
  that queued it. `jobs/later db queue name args t` queues the job `name`
  with a map of strings, to run at `t` or after. `jobs/worker db queue
  performers` works a queue until the process ends: `performers` maps each
  name to a function of the session and the arguments. A worker claims a job
  with `for update skip locked`, so two workers never take the same one, and
  holds it for five minutes, after which a worker that died leaves it to
  another. A job that succeeds is deleted. One that fails waits attempts^4 +
  2 seconds and runs again, and after five attempts it stays in the table
  with the reason. `jobs/worked` takes one step of that loop at a moment the
  caller names, which is how `spec/db/jobs` runs it. `jobs/beside connect
  queue performers served` runs a worker in a fiber beside `served`, such as
  `web/serve`, which is how the guestbook sends its mail.
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
- `data`: what an action running in the browser reads from the server.
  `data/ask "stock/low" [3]` asks the provider the app named `stock/low`,
  `data/all [a b]` asks for several in one request, and `data/then a f`
  goes on with what came back:

  ```
  pub fn opened s
    asks = [(data/ask "stock/low" [3]) (data/ask "orders/recent" [2])]
    data/then (data/all asks) (xs -> put (put s "low" xs[1]) "recent" xs[2])
  ```

  With `derive data/providers` an action calls a provider as it calls any
  function. A provider is a function whose first two parameters are the
  viewer and a database session (`low viewer db n`); where the app calls it
  with two arguments fewer, as `stock/low 3`, the derivation writes that
  function into the provider's module, which asks the server, and writes
  `provided`, the table `web/providers` answers from. A provider no code
  calls that way is not reachable from a page, so a server action, which takes
  the state after the viewer and the session, stays closed. The entry imports
  each provider's module, as an app imports `./views` for kata. A provider
  may sit in a resource's module beside its actions; `routes/rest` gives it
  no route. The browser's entry compiles the provider's body without running
  it, so a provider that reads through a model needs the browser's entry to
  `derive models/tables` and import the migrations, as the server's does
  (`examples/pantry`).

  An action that asks answers what it asks for instead of its next state.
  The page sends every call one round holds to `POST /senro/data` in one
  request, then runs the action again with the answers; the action is a
  function of its state and those answers alone, so it comes to the same
  question and goes on past it. A call that needs another's answer, inside
  `data/then`, waits a round; calls that need none share one. The server
  names its providers with `web/providers routes secret stock/provided`, or
  with a table of its own, `{ "stock/low": low_from_page }`, each a function
  of the viewer, a database session and the arguments as a list, answering
  an effect. Anyone signed in can call a provider
  with arguments of their choosing, so it checks what the viewer may read,
  as a model's policy does (`spec/runs/provided`).
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
