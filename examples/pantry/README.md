# pantry

A shelf of things with counts: add an item, step its count up or down, rename
it in place, remove it. Every change is a form the server answers with the
whole page, and senro's page script morphs that page into the live one, so
the browser never reloads and the app holds no JavaScript of its own. Once
the pantry's browser module has loaded, the page arrives as data and the
module renders it.

```
KANSO=kanso sh browser/build.sh examples/pantry <runtime.wasm>
cd examples/pantry && PGHOST=127.0.0.1 PGPORT=54329 PORT=3001 kanso run .
```

The server reads `public/` under the directory it starts in, which holds the
stylesheet and the browser module, so it runs from the pantry's own
directory. Started from senro's root, the page arrives unstyled and the
planner does nothing.

`PORT=3001` serves it beside the guestbook, against the same Postgres, and
it makes its `items` table on first run.

- `items.kso` is the resource: `index`, `create`, `edit`, `update` and
  `destroy`, each a REST route by its name. `update` takes two forms, one
  renaming the item and one stepping its count by `by`.
- `items.kso` holds no SQL. It reads the shelf with `item/all db` and one
  item with `item/find db id`, and writes with `item/create`,
  `item/update` and `item/destroy`.
- The plus, minus and remove buttons are forms that POST with a `_method`
  field of `PATCH` or `DELETE`, which senro reads as the method they stand
  for.
- `views/shelf.kata` is the page and `views/layout.kata` the frame around it.
  An item open for editing is rendered as a form with `autofocus`, and the
  page script focuses it when the morph brings it in. `items.kso` describes
  the page with `views/shelf_view` and answers with `views/answer`.
- `browser.kso` is what the browser runs: the planner, a component whose
  counting never reaches the server, and the pages, rendered from the data
  the server sends.
- The planner's check button asks the server which staples the week would
  run short of. Its action calls `item/short meals`, a provider in
  `item.kso` that reads the starred items through the item's model. The
  page sends that call to `/senro/data`, gets the names back, and runs the
  action again with them; one click is one request.
