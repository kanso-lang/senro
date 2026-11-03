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

The actions run in the browser. The app builds its browser module
(`browser.kso`, built by `browser/build.sh`), and a click runs the action
there without asking the server, then morphs the component's next rendering
into place.

## What it does not do yet

- A diagnostic in a template points at the module's derived source. The
  comments there name the template's lines, but the message itself should.
- No `case` and no whitespace control.
