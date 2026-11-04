# pantry

A shelf of things with counts: add an item, step its count up or down, rename
it in place, remove it. Every change is a form the server answers with the
whole page, and senro's page script morphs that page into the live one, so
the browser never reloads and the app holds no JavaScript of its own. Once
the pantry's browser module has loaded, the page arrives as data and the
module renders it.

```
KANSO=kanso sh browser/build.sh examples/pantry <runtime.wasm>
kanso run examples/pantry
```

It serves on port 3001 against the Postgres the guestbook uses, at
127.0.0.1:54329, and makes its `items` table on first run.

- `items.kso` is the resource: `index`, `create`, `edit`, `update` and
  `destroy`, each a REST route by its name. `update` takes two forms, one
  renaming the item and one stepping its count by `by`.
- The plus, minus and remove buttons are forms that POST with a `_method`
  field of `PATCH` or `DELETE`, which senro reads as the method they stand
  for.
- `views/shelf.kata` is the page and `views/layout.kata` the frame around it.
  An item open for editing is rendered as a form with `autofocus`, and the
  page script focuses it when the morph brings it in. `items.kso` describes
  the page with `views/shelf_view` and answers with `views/answer`.
- `browser.kso` is what the browser runs: the planner, a component whose
  clicks never reach the server, and the pages, rendered from the data the
  server sends.
