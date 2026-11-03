# Pages that update in place

`PRINCIPLES.md` sets the goal: an app that feels like a single-page
application while its author writes ordinary server code. This note is the
plan for getting there, and it is deleted when the work has shipped.

## What has to travel

An action today calls a kata view with kanso values and answers HTML:
`views/signed signed name flash`. For the browser to render instead, the
browser needs the view and the values. The view is the easy half: kata
compiles a template to a kanso function, and kanso's playground already turns
a program into a wasm module and runs it, through the emitter's IR and
`ir_wasm`, against the runtime built for wasm32. The values are the hard
half. A record does not cross a module boundary in kanso, and JSON carries
maps, so a `signature` sent as JSON comes back as a map that `e.message` cannot
read.

senro can close that gap without a change to the language. The models
derivation already knows every record an app's views read, field by field,
so a derivation can write each record's JSON reader the way it writes
`signature_from row` today. A view's locals then travel as JSON and arrive as
the same records the server built.

## Two steps

**1. Morph.** The first request answers a whole page, as now. A small script
then takes over links and forms: it asks for the next page with a header that
says so, and the server answers only the HTML inside the layout. The script
morphs the live document toward it, keeping focus, scroll and form state where
the elements match. This already removes the full reload, and it fixes the
transport the second step uses. Spec: a request with the header answers the
body a full request would have wrapped, byte for byte.

**2. Data.** An action answers a view and its locals as a value instead of a
string, such as `web/view "signed" (views/signed_locals signed name flash)`.
The server renders it as HTML for a first request and answers its locals as
JSON for the script. `kanso build` gains a wasm32 target that writes the
app's views as a module, the browser renders the locals with it, and the
script morphs as in step 1. Spec: for each view in the guestbook, the HTML
the browser's module renders from the JSON equals the HTML the server
renders, byte for byte.

## Open edges, decided as they come

- Morphing: a small morph written for senro, or idiomorph vendored. Prefer
  the smaller one that keeps the spec's byte-for-byte check.
- Encoding: JSON first; a binary encoding only if a measurement says the
  JSON is the cost.
- Caching: the views module is fingerprinted and cached forever. A deploy that
  changes a view changes the fingerprint, and the script reloads the page
  once.
- Firefox is the browser this is tuned and tested in first.
