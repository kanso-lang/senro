# Pages that update in place: what is left

`PRINCIPLES.md` sets the goal: an app that feels like a single-page
application while its author writes ordinary server code. Most of the way
there has shipped and is described in the READMEs: the page script morphs
each answer into the live page, pages follow each other's changes over
`/senro/live`, and components run their actions in the browser as wasm or on
the server behind policies, with loading hooks for the moment before the
module arrives. This note keeps what is still to build, and it is deleted
when that has shipped.

## Views rendered in the browser

A page still travels as HTML: an action calls a kata view and answers the
markup, and the script morphs it in. The next step sends a view's locals
instead, as JSON, and the browser renders them with the app's views compiled
to wasm, the way it already runs components.

The views are the easy half, since `kanso build --wasm` already turns them
into a module. The values are the hard half. A record does not cross a
module boundary in kanso, and JSON carries maps, so a `signature` sent as
JSON comes back as a map that `e.message` cannot read. senro can close that
gap without a change to the language: the models derivation already knows
every record an app's views read, field by field, so it can write each
record's JSON reader the way it writes `signature_from row`.

An action would answer a view and its locals as a value, such as
`web/view "signed" (views/signed_locals signed name flash)`. The server
renders it as HTML for a first request and answers its locals as JSON for
the script. Spec: for each view in the guestbook, the HTML the browser's
module renders from the JSON equals the HTML the server renders, byte for
byte.

## Caching the module

The browser module is fetched on every page load today. It should be keyed
by the app's version and kept in the browser's Cache Storage, so a visitor
downloads it once per deploy and a returning visitor has it before the page
finishes parsing. A deploy that changes it changes the fingerprint, and the
script reloads the page once.

## Reaching JavaScript

A component will want a JavaScript library now and then, a charting or
mapping library in particular. That needs a way for kanso code in the
browser to call into JavaScript and be called back, which is a question
about the language itself (kanso#2284, parked until an app needs it).

## Open edges, decided as they come

- Encoding: JSON first; a binary encoding only if a measurement says the
  JSON is the cost.
- Firefox is the browser this is tuned and tested in first.
