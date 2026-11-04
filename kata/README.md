# kata: templates compiled to kanso

kata is senro's view layer (kanso#2178). A view is a `.kata` file, and kata
compiles it to a kanso function while the app compiles. The syntax borrows
Slim's indentation and tag shorthand and otherwise follows kanso: holes are
written `{expr}` as in a kanso string, control lines are bare `if` and `for`,
and a comment starts with `#`.

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
  for e in signatures
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
  tag or a `|` may hold `{expr}`, also escaped. `\{` is a brace.
- `if expr`, any number of `else if expr`, an optional `else`, and
  `for x in xs`.
- `# comment` drops the line and the rows under it. `doctype html` writes the
  doctype.

## What it writes

The template becomes a `pub fn` named after the file. Each `if` branch and
each `for` body becomes a helper function of exactly the names in scope it
mentions, because kanso refuses an unused parameter; a body that mentions none
becomes a constant. Markup and holes are packed into string literals that fit
kanso's 80 columns, and a comment above each literal names the template lines
its holes came from.

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
names the component and holds its state as JSON, and writes `act`, which runs
an action by the name a template bound it under.

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
it, and answers with `answer`:

```
page = views/signed_view signed name flash removals
views/answer req (views/layout_view "Guestbook" page)
```

Once the app names `answer` or `rendered`, kata writes three more functions
for each page in the module:

- `signed_view` takes what `signed` takes and answers the page as data: the
  template's name and its values. A record goes in cut down to a map of the
  fields the template reads. `for e in signatures` followed by `e.name`
  reads `name` from each record in `signatures`, so each record becomes a
  map of `name` and the other fields read beside it. A value the template
  reads no field of goes in whole. A page may hold another page as a value,
  which is how a layout holds its body.
- `signed_keyed` is the template compiled a second time, with each field
  read written as a read of a map's key, so it renders from the data.
- `rendered` renders a page from its data, choosing the template by name.

`answer` renders the page on the server for a request the browser made
itself. senro's page script asks with a `senro-view` header and gets the
page's data as JSON, which the app's browser module renders with the same
`rendered` before the script morphs it into the page. Because the server
renders with `rendered` too, the HTML a first request gets and the HTML the
browser renders come from one compile. `spec/runs/pages` prints both beside
the template's rendering of the records themselves, and the three are the
same bytes.

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

A template cannot yet read a record held inside a record, whether it renders
records or data. A loop that walks something other than a value the template
takes, or one of its fields, leaves the fields read in its body out of the
data.

## What it does not do yet

- A diagnostic in a template points at the module's derived source. The
  comments there name the template's lines, but the message itself should.
- No `case` and no whitespace control.
