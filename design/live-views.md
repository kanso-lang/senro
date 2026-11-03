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

## Dynamic parts

Clay's refinement: every page renders on the server and arrives as HTML, and
only the parts that are dynamic wait for the app. A dynamic part, such as a
map that pans or a list that filters as you type, is a component written in
kanso against senro's own DOM library, which wraps what the browser offers so
that app code never touches JavaScript. The server renders each component's
first state into the page, so it shows at once. When the views module arrives
the component starts handling events in the browser.

Until then the component is inert, and senro says so: it gives the page one
hook for that state, so an app can show a line such as "application loading,
one moment" and let it disappear when the module starts. A page with no
dynamic parts never waits for anything.

The views module is keyed by the app's version and kept in the browser's
Cache Storage, so a visitor downloads it once per deploy. A visitor who comes
back gets the cached module before the page has finished parsing.

## Reaching JavaScript

A component will want a JavaScript library now and then, a charting or
mapping library in particular. That needs a way for kanso code in the browser
to call into JavaScript and be called back, which is a question about the
language itself (an effect or builtin kind that only the browser engine
answers). It goes to Clay as its own issue when a component first needs it.

## Open edges, decided as they come

- Morphing: a small morph written for senro, or idiomorph vendored. Prefer
  the smaller one that keeps the spec's byte-for-byte check.
- Encoding: JSON first; a binary encoding only if a measurement says the
  JSON is the cost.
- Caching: the views module is fingerprinted by the app's version. A deploy
  that changes it changes the fingerprint, and the script reloads the page
  once.
- Firefox is the browser this is tuned and tested in first.
