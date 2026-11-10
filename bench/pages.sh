#!/bin/sh
# What a page costs to send and to show, counted. The benchmark is the app in
# bench/pages: a board of fifty topics inside a layout, with a reading list
# component on it. Its rows are in bench/pages.golden, which says what each
# one counts.
#
#   KANSO=...  KANSO_RUNTIME_WASM=...  KANSO_COUNT=...  sh bench/pages.sh [--write]
#
# KANSO_COUNT is kanso's count_module example, built in a kanso checkout with
# `cargo build --release --example count_module`. It runs a wasm module once
# and reports the instructions executed, the same on every machine. The
# server's entries are built for wasm too and counted the same way, because
# that count can be pinned and a native one cannot.
#
# Without --write the rows are compared with the golden, and a difference
# fails. With it the golden's rows are rewritten and its header kept.
set -e
cd "$(dirname "$0")/.."
KANSO=${KANSO:-kanso}
golden=bench/pages.golden
for need in KANSO_RUNTIME_WASM KANSO_COUNT; do
  eval "set_to=\${$need:-}"
  if [ -z "$set_to" ]; then
    echo "bench/pages.sh: $need is not set" >&2
    exit 2
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for entry in records data html browser; do
  (cd bench/pages && "$KANSO" build "$entry.kso" --wasm > "$work/$entry.build" 2>&1) || {
    cat "$work/$entry.build" >&2
    exit 1
  }
  mv "bench/pages/$entry.wasm" "$work/$entry.wasm"
  rm -f "bench/pages/$entry.ll"
done

# One run: the module's output in $work/$1.out, and the count on stdout.
counted() {
  name=$1
  module=$2
  shift 2
  "$KANSO_COUNT" "$KANSO_RUNTIME_WASM" "$work/$module.wasm" "$@" \
    > "$work/$name.out" 2> "$work/$name.err" || {
    cat "$work/$name.err" >&2
    exit 1
  }
  sed -n 's/^instructions=//p' "$work/$name.err"
}

records=$(counted records records)
data=$(counted data data)
html=$(counted html html)

# The browser module is handed the page's data as the page script hands it
# over, and an action as a click does: the component, the action, the state
# the page holds and the answers so far.
printf '\n\n' > "$work/page.event"
cat "$work/data.out" >> "$work/page.event"
printf 'x' > "$work/none.event"
node -e '
  const fs = require("fs");
  const html = fs.readFileSync(process.argv[1], "utf8");
  const held = /data-state="([^"]*)"/.exec(html)[1];
  const state = held.replace(/&quot;/g, "\"").replace(/&#39;/g, "\x27")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
  fs.writeFileSync(process.argv[2], state);
  fs.writeFileSync(process.argv[3], ["reading", "saved_next", state, "[]"].join("\n"));
' "$work/html.out" "$work/state" "$work/act.event"

start=$(counted start browser "SENRO_EVENT=@$work/none.event")
page=$(counted page browser "SENRO_EVENT=@$work/page.event")
act=$(counted act browser "SENRO_EVENT=@$work/act.event")

# The page the module rendered from the data is the page the server sent a
# browser that asked for the page.
printf '\n' >> "$work/html.out"
if ! cmp -s "$work/html.out" "$work/page.out"; then
  echo "bench/pages.sh: the module's page differs from the server's" >&2
  diff "$work/html.out" "$work/page.out" | head -5 >&2
  exit 1
fi

rows="page_bytes=$(wc -c < "$work/data.out" | tr -d ' ')
state_bytes=$(wc -c < "$work/state" | tr -d ' ')
server_records_instructions=$records
server_data_instructions=$data
server_html_instructions=$html
browser_start_instructions=$start
browser_page_instructions=$page
browser_act_instructions=$act"

if [ "${1:-}" = "--write" ]; then
  { grep '^#' "$golden"; echo "$rows"; } > "$work/golden"
  cp "$work/golden" "$golden"
  echo "$rows"
  exit 0
fi
echo "$rows" > "$work/rows"
grep -v '^#' "$golden" > "$work/want"
if cmp -s "$work/want" "$work/rows"; then
  echo "bench/pages: every row reads as bench/pages.golden pins it"
  exit 0
fi
echo "bench/pages: rows differ from bench/pages.golden (golden <, here >)" >&2
diff "$work/want" "$work/rows" >&2 || true
echo "=== every row as measured here, to copy into the golden" >&2
echo "$rows" >&2
exit 1
