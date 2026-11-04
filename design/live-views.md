# Pages that update in place: what is left

`PRINCIPLES.md` sets the goal: an app that feels like a single-page
application while its author writes ordinary server code. Most of the way
there has shipped and is described in the READMEs: the page script morphs
each answer into the live page, pages follow each other's changes over
`/senro/live`, components run their actions in the browser as wasm or on the
server behind policies, and pages travel as data and are rendered in the
browser by the app's views compiled to wasm. This note keeps what is still
to build, and it is deleted when that has shipped.

## Caching the module

The browser module is revalidated on each page load: the server answers its
ETag with a 304, so a visitor downloads it once per change to it. What is
left is keeping it in the browser's Cache Storage under the app's version,
so a returning visitor has it before the page finishes parsing, with no
request at all. A deploy that changes the version makes the script reload
the page once.

## Reaching JavaScript

A component will want a JavaScript library now and then, a charting or
mapping library in particular. That needs a way for kanso code in the
browser to call into JavaScript and be called back, which is a question
about the language itself (kanso#2284, parked until an app needs it).

## Open edges, decided as they come

- Encoding: JSON first; a binary encoding only if a measurement says the
  JSON is the cost.
- A page's data holds the fields its templates read, and a record held
  inside a record cannot be read yet (`kata/README.md`).
- Firefox is the browser this is tuned and tested in first.
