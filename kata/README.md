# kata: templates compiled to kanso

kata is senro's view layer (kanso#2178). A view is a `.kata` file, and kata
compiles it to a kanso function while the app compiles. The syntax borrows
Slim's indentation and tag shorthand and otherwise follows kanso: holes are
written `{expr}` as in a kanso string, a test is a bare `if`, a list is walked
with `each`, and a comment starts with `#`.

## Using it

Templates live in a directory of their own, which holds no kanso source. The
app's entry imports that directory and names the derivation:

```
import "../../kata"
import "./views"

derive kata/views
```

Each `.kata` file in a module the entry imports becomes a pub function of
that module, named after the file. `views/signed.kata` is called as
`views/signed`. The compiled function is ordinary kanso: `kanso check` reads
its field accesses and its parameters, and both engines run it.
`kanso derived` prints the source kata wrote.

## The format

```
takes signatures name flash
header
  h1 Guestbook
if flash != ""
  p.flash = flash
form method="post" action="/entries"
  input name="name" value=name
  button Sign
ol.entries
  each signatures e ->
    li
      p.message = e.message
      p.who By {e.name}
```

- A first line `takes a b c` names the template's parameters, in order.
- Nesting is by indentation, and tags are closed for you. Void elements
  (`meta`, `img`, `br` and the rest) get no closing tag.
- `tag.class#id` is shorthand, and a bare `.class` or `#id` means a `div`. A
  `class` attribute is joined onto the shorthand's classes.
- Attributes are `name="text"`, where the text may hold `{expr}`, or
  `name=expr` for a value.
- `= expr` writes a value escaped and `== expr` writes it raw. Text after a
  tag or a `|` may hold `{expr}`, also escaped. `\{` is a brace. A value
  that may be none, such as a map's entry, writes nothing under `=`.
- `if expr`, any number of `else if expr` and an optional `else`.
- `each xs x ->` writes the rows under it once for each element of `xs`,
  with `x` in scope. It is the call `each xs (x -> ...)` to a helper kata
  writes, with the rows as the function's body, in the order `list/map`
  takes its arguments. Kata has no `for`, as kanso has none, and a `for` row
  is refused at its line (`spec/errors/a_for_row_in_a_template`).
- `case expr` with `when value` rows under it and an optional `else` last.
  A value is matched as a function's argument is: a string, a number,
  `true`, `false` or `none`. A value no `when` names writes the `else` rows,
  or nothing (`spec/runs/case`).
- `# comment` drops the line and the rows under it. `doctype html` writes the
  doctype.

## What it writes

The template becomes a `pub fn` named after the file. Each `if` branch and
each `each` body becomes a helper function of exactly the names in scope it
mentions, because kanso refuses an unused parameter; a body that mentions none
becomes a constant. A `case` becomes a function with an arm for each `when`,
each binding only the names its own rows read. Markup and holes are packed into string literals that fit
kanso's 80 columns. A literal holds the holes of one template line, and a
`# from list.kata:6` comment above it names that line; one above the function
names the `takes` line. kanso reads these comments back, so a mistake in a
template is reported with the template line under the derived one
(`spec/errors/a_template_typo`).

Partials and layouts need nothing of their own, because every template in a
directory is a function of one module. A layout is a template that takes the
page and writes it with `== body`, and a page uses it with
`== layout "Profile" (card user)`.

kata also writes three helpers into each module that holds templates:
`escape`, `each` and `joined`. They belong in the standard library once the
design settles.

## Components

A template that binds an action is a component. `on-click=more` on an
element binds a click on it to the function `more` in the template's module:

```
takes meals
div.planner
  span.count = meals
  button on-click=fewer −
  button on-click=more +
```

```
pub fn more meals
  meals + 1

pub fn fewer meals
  if (meals > 0) (meals - 1) 0
```

A component takes one value, its state, and an action takes the state and
answers the next one. kata wraps what the template draws in an element that
names the component and holds its state as its bytes in base64 (`wire`), and
writes `act`, which runs an action by the name a template bound it under.

Where an action runs depends on its parameters. One that takes only the
state runs in the browser: the app builds its browser module (`browser.kso`,
built by `browser/build.sh`), and a click runs the action there without
asking the server. An action that also asks for `req` or `db` needs the
server, and so does every action of its component. The click posts the
state to `/senro/act/<component>`, which `web/components` adds to the
route table for each server component the app names. Only an action a
template binds can be reached that way, and only by a request carrying the
page's `senro-page` header. A server action may also ask for `viewer`, the
id the session signed in, and it writes through a model
(`models/updated`, `models/destroyed`), whose policy decides; kata refuses
one that calls `pg/query` or `pg/run` itself. In both cases the page morphs
the component's next rendering into place.

## Pages in the browser

A template that binds no action is a page, and an app can have its pages
rendered in the browser. The action describes the page instead of rendering
it, and answers with `answer`, or with `answer_as` and a status:

```
page = views/signed_view book form flash removals
views/answer req (views/layout_view "Guestbook" page)
```

Once the app names `answer` or `answer_as`, kata writes `signed_view` for
each page in the module. It takes what `signed` takes and answers the page:
those values, a function that writes them onto bytes, and a function that
draws them as markup. A page may hold another page as a value, which is how
a layout holds its body.

`answer` and `answer_as` draw the page on the server for a request the
browser made itself. senro's page script asks with a `senro-view` header
and gets the page as bytes, which the app's browser module reads and draws
before the script morphs the result into the page.

The bytes have no field names in them. kata reads a page's shape from its
template: `each signatures e ->` followed by `e.name` reads `name` from each
record in `signatures`. So it writes a record as the fields the template
reads, in a fixed order, and a list of records as a count and the records.
A value the template reads no field of is written behind a one-byte tag
that says what it is. `wire/wire.kso` describes the tags.

A program that names `rendered`, as the browser module does, gets the other
half: a record type for each record a template reads fields from, a reader
that builds those records from the bytes, and `rendered`, which picks the
page by its number and draws it with the same `signed` the server draws
with. The server and the browser were both compiled from the templates, so
they agree on the order. A page's bytes open with four that mark the
module's shapes, a hash of what each template takes and reads, and
`rendered` draws nothing from bytes that open any other way. A browser
still running an older deploy's module reloads the page.

A server gets the packers and not the readers. That keeps a misspelled field
a compile error: the packer reads `e.nmae` from the app's records, which
have no such field. The reader's record types hold every field a template
names, so a program with them cannot tell.

`spec/runs/pages` draws one page from its records, from its bytes and by
calling the templates directly, and the three are the same bytes. Its event
is the page's bytes, and the browser module draws the same page from them
natively, interpreted and as wasm. A template named `answer`, `answer_as`,
`rendered` or `packed` is refused, since it would take one of these names.

The browser module hands `rendered` to `browser/answer_pages`, with the
app's browser components, here none:

```
import "../../browser"
import "../../kata"
import "./views"

derive kata/views

browser/answer_pages {} views/rendered
```

A program that names `rendered` but not `answer`, as this one does, holds
none of the records the pages read. kata writes a page's own function and
its `_view` there only when the program names them.

A template reads through a record held inside a record, as
`p.author.name`, and the page's data keeps the fields of the inner record
the template reads (`spec/runs/nested_reads`). A loop that walks something
other than a value the template takes, or one of its fields, leaves the
fields read in its body out of the data.

## What it does not do yet

- No whitespace control.
