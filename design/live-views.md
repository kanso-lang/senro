# Pages that update in place: what is left

`PRINCIPLES.md` sets the goal: an app that feels like a single-page
application while its author writes ordinary server code. Most of the way
there has shipped and is described in the READMEs: the page script morphs
each answer into the live page, pages follow each other's changes over
`/senro/live`, components run their actions in the browser as wasm or on the
server behind policies, and pages travel as data and are rendered in the
browser by the app's views compiled to wasm, in bytes kata derives from
each page's shape. This note keeps what is still to build, and it is deleted
when that has shipped.

## Reaching JavaScript

A component will want a JavaScript library now and then, a charting or
mapping library in particular. That needs a way for kanso code in the
browser to call into JavaScript and be called back, which is a question
about the language itself (kanso#2284, parked until an app needs it).

## Later, each measured first

These are recorded and not yet built (kanso#2418). Each gets a benchmark
before it gets code.

**Keyed list matching.** The morph in `web/script.kso` matches an
element's children by position. A list that gains an item at the top has
every element after it patched to look like its neighbour, where moving
the existing elements would do. Matching on a stable key fixes that: an
element's id, or a key kata derives from a record's id. `moveBefore()`
moves an element without resetting its focus, its playback or its iframe,
and Chrome has shipped it (whatwg/dom#1255), so the morph uses it where it
exists and `insertBefore` elsewhere.

**Compiled updates.** kata knows which fields each part of a template
reads. It could compile a template into direct updates for the browser
module, in the way Svelte and Solid do: when `meals` changes, set the text
of the one node that shows it, with no HTML built, nothing parsed and no
tree walked. An update would then cost what changed, whatever the size of
the page.

Keyed matching goes first of the two, because its cost is concrete and
known. Compiled updates follow only if a benchmark shows the morph is the
cost.

**Declined: a virtual DOM.** It would replace the HTML string and the
browser's own parser with a tree of objects built across the boundary
between wasm and JavaScript, which likely costs more than it saves.
Compiled updates do better than both.
