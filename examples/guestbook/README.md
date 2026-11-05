# The guestbook, as a senro prototype

The first application senro is built for (kanso#2178). It uses `net/dial` and
`net/read_bytes`, the Postgres client in `../../pg`, derivations (kanso#2186),
sha256's HMAC and PBKDF2 with base64, and a view kata wrote.

```
kanso run examples/guestbook      # Postgres on 127.0.0.1:54329, trust login
kanso derived examples/guestbook  # the schema and route table derived
KANSO=kanso sh browser/build.sh examples/guestbook <runtime.wasm>
```

`kanso run` builds at kanso's development tier, where a password takes
seconds to stretch at the default rounds; `SENRO_PASSWORD_ROUNDS=1000` in
the environment makes signing up and in quick while developing.

The third line builds the browser module the page loads, which renders the
guestbook's pages in the browser. Without it the pages still update in
place, rendered on the server.

- `main.kso` connects, creates each table the schema names if it is
  missing, compares the database's tables with the schema it was compiled
  with, and serves the route table that `derive routes/rest` declares. A
  table that differs, say one an older build made with another column, stops
  the app before it serves anything, with each difference named.
- `migrations.kso` keeps the schema as the changes that built it, as a pub
  constant. `derive models/tables` folds them into `schema` while the app
  compiles, and refuses a record type whose table is missing or whose field
  has no column: `mesage` in `entries/signature` is a compile error at the
  type.
- `../../routes` is the convention: `home/index` answers GET /, `entries/index`
  GET /entries, `entries/create` POST /entries, `entries/show` GET
  /entries/:id, and `new`, `edit`, `update` and `destroy` the rest of the
  REST set. Any other pub function in the app's modules is refused where it
  is declared, so `entries/destory` is a compile error rather than a route.
  Two routes that can answer the same request are refused at the later one:
  `entries/show` taking `id` beside `entries/new` is an error until `id` is
  annotated `id:int`.
- `../../web` serves the table and decodes a posted form. Each connection is
  answered in a fiber of its own, with a database session borrowed from the
  server's pool (see senro's README), so a slow request holds up nobody
  else. A path whose segment after the module names no route is tried as
  `:id`, and an `id:int` action is handed the number or answers 404. A path
  under `public/` is served as a file, which is where the stylesheet comes
  from.
- A visitor signs the book with an account. `account.kso` declares the
  `account` model, a name, a password digest and an email address, and its
  actions. It is a singular resource, since a visitor only ever has the one:
  `account/new` and `account/create` answer GET /account/new and POST
  /account. A name or an address already taken, an address with no `@`, or
  a password under eight characters, brings the form back with a 422.
  Otherwise the password is digested with `passwords/digested`, the account
  is made through its model, and its address is mailed a link to confirm.
  GET /account/edit lets a signed-in visitor choose a new password, and
  PATCH /account checks the current one before setting it, ten tries in
  three minutes, as Devise's registrations do. `session.kso` is a singular
  resource too: GET /session/new is the sign-in form, POST /session checks
  the password with `passwords/matches?`, and a DELETE signs out. A wrong
  password and a name with no account get the same message, after the same
  work.
- A visitor who has lost a password follows "Forgot your password?" on the
  sign-in form to `resets.kso`. GET /resets/new asks for the address, and
  POST /resets mails a link to it when an account has it, answering the same
  either way. The link is GET /resets/:id/edit, where the id is a token from
  `passwords/reset_token`, signed over the account and the digest it keeps;
  PATCH /resets/:id sets the new password. Setting it changes the digest, so
  the link works once, and it stops working after fifteen minutes. Setting a
  password this way also confirms an address that was not yet, since the
  link proves the visitor reads its mail. Every sign-in rests on the digest
  the account kept when it was made (`session/signed_against`), so setting
  a password, even the same one, signs out every older session at its next
  action that needs a sign-in. A password changed from the account page
  signs the browser that changed it in again on the new digest, so only the
  others are signed out.
- A new account confirms its address before it can sign in, as Devise's
  `confirmable` asks. Sign-up mails a link and does not sign the visitor in;
  signing in with the right password before confirming is refused with a
  403, and the link is sent again. The link is GET /confirmations/:id/edit,
  which shows a button and changes nothing, so a mail scanner that fetches
  every link confirms nobody; the button's PATCH /confirmations/:id stamps
  the account's `confirmed` column. The token is bound to the address and
  to that column being empty, so it works once, and it lasts a day.
- Three wrong passwords in a row lock an account, as Devise's `lockable`
  does (`session/locks_after`). The third mails a link to unlock it, and
  the lock ends by itself after an hour (`session/locked_minutes`). A wrong
  password on a locked account is answered as any wrong password is, and
  only the right one is told that the account is locked. The link is GET
  /unlocks/:id/edit, a button again, and PATCH /unlocks/:id clears the lock;
  its token is bound to the moment of the lock, so it works once. A right
  password ends a run of wrong ones, and so does a password reset, which
  also unlocks.
- `account_mailer.kso` holds the letters and the links they carry, which
  start with `mail/url_for`. A module whose name ends in `_mailer` is no
  resource, so `account`, `session`, `resets`, `confirmations` and
  `unlocks` can all call it. Mail goes where `SENRO_MAIL` says (see senro's
  README); unset, it is printed to standard error, which is where a
  developer finds the link.
- Signing in keeps the account's name in the session, a cookie signed with
  HMAC-SHA-256, as its viewer; a cookie whose signature does not match reads
  as an empty session. `entries/create` signs with the viewer's name, so
  nobody can sign as someone else, and sends a visitor who is not signed in
  to the sign-in form. After a signature is stored it answers a redirect to
  the list, so reloading the page does not post the form again, and carries
  a one-time notice across it in the session.
- `signatures.kso` declares the `signature` model, its policies and its
  rules: a name and a message, and a message under 280 characters. Only
  the account that signed an entry may remove it.
  `entries.kso` makes a signature through the model (`models/created`),
  which stores it with a parameterized insert, so what a visitor types is
  stored as text and never read as SQL. A signature that breaks a rule is
  not stored: the page comes back with a 422, the form as the visitor
  filled it in, and each problem beside its field.
- `views/signed.kata` is the page and `views/layout.kata` the frame around
  it. `derive kata/views` in `main.kso` compiles each to a function of the
  `views` module while the app compiles. The page reads the `signature`
  records `entries.kso` builds by their fields, which needs no import.
  `entries.kso` describes the page with `views/signed_view` and answers
  with `views/answer_as`, 200 or 422: HTML to a browser that asked for the
  page itself, and the page as JSON to senro's script once `browser.kso`,
  built for the browser, has loaded and can render it.
