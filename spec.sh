#!/bin/sh
# senro's specs, run against the kanso the repo pins (.kanso-version):
#
#   KANSO=/path/to/kanso sh spec.sh
#
# Every module and example checks clean; the guestbook derives the schema,
# route table and views its golden holds; each app under spec/runs prints its
# golden on both engines, and one with a browser module answers its events
# natively, interpreted and as wasm; spec/runs/pages renders a page in the
# browser module as the server rendered it; each app under spec/db, run
# against a live Postgres, prints its golden on both engines; each app under
# spec/serve, served and asked over HTTP, answers its golden; the guestbook
# and the pantry, used in a browser, update in place without a reload; the
# generators write examples/notebook, which checks and serves its resource;
# and each app under spec/errors is refused with the message its golden
# holds.
# Set SPEC_WRITE=1 to rewrite the goldens from what this kanso says.
set -u
KANSO=${KANSO:-kanso}
# Passwords are stretched by thirty rounds of PBKDF2, so the interpreter
# signs a visitor in quickly; spec/runs/passwords checks that the setting
# reaches the digest.
export SENRO_PASSWORD_ROUNDS=30
fail=0
here=$(pwd)

note() { echo "$1"; }
bad() { echo "FAIL: $1"; fail=1; }

note "== every module and example checks"
for d in routes models web pg kata mail jobs passwords tokens generate examples/guestbook examples/notebook examples/pantry examples/pg; do
  if out=$("$KANSO" check "$d" 2>&1); then
    note "ok: $d"
  else
    bad "$d"
    echo "$out"
  fi
done

note "== the guestbook derives its schema and routes"
got=$("$KANSO" derived examples/guestbook 2>&1)
if [ "${SPEC_WRITE:-}" = 1 ]; then
  printf '%s\n' "$got" > spec/guestbook.derived
fi
if printf '%s\n' "$got" | diff spec/guestbook.derived - >/dev/null; then
  note "ok: spec/guestbook.derived"
else
  bad "spec/guestbook.derived"
  printf '%s\n' "$got" | diff spec/guestbook.derived -
fi

note "== each app under spec/runs prints its golden, natively and interpreted"
for d in spec/runs/*/; do
  name=$(basename "$d")
  want="spec/runs/$name.stdout"
  for engine in native interp; do
    if [ "$engine" = interp ]; then
      got=$(cd "$d" && "$KANSO" run . --interp 2>&1)
    else
      got=$(cd "$d" && "$KANSO" run . 2>&1)
    fi
    if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
      printf '%s\n' "$got" > "$want"
    fi
    if printf '%s\n' "$got" | diff "$want" - >/dev/null; then
      note "ok: $name ($engine)"
    else
      bad "$name ($engine)"
      printf '%s\n' "$got" | diff "$want" -
    fi
  done
done

note "== each browser module answers its events on every engine"
# An app under spec/runs with a browser.kso and a list of events in
# spec/runs/<app>.events, one to a line as the component, the action and the
# state separated by tabs, answers each as spec/runs/<app>.answers holds,
# natively, interpreted and built for the browser. A page is an event with no
# component and no action, whose state is the page as data. The browser build is run
# by spec/browser/module.mjs against the kanso runtime for wasm32 named by
# KANSO_RUNTIME_WASM, and is skipped without it.
tab=$(printf '\t')
for events in spec/runs/*.events; do
  name=$(basename "$events" .events)
  d=spec/runs/$name
  want=spec/runs/$name.answers
  engines="native interp"
  built=$(mktemp -d)
  if [ -n "${KANSO_RUNTIME_WASM:-}" ]; then
    if (cd "$d" && "$KANSO" build browser.kso --wasm > /dev/null 2>&1); then
      mv "$d/browser.wasm" "$built/app.wasm"
      engines="$engines wasm"
    else
      bad "$name builds for the browser"
    fi
    rm -f "$d/browser.ll"
  else
    note "SKIPPED: $name as wasm (no KANSO_RUNTIME_WASM)"
  fi
  for engine in $engines; do
    got=$(while IFS= read -r line; do
      event=$(printf '%s' "$line" | tr "$tab" '\n')
      case $engine in
        native) (cd "$d" && SENRO_EVENT="$event" "$KANSO" run browser.kso 2>&1) ;;
        interp) (cd "$d" && SENRO_EVENT="$event" "$KANSO" run browser.kso --interp 2>&1) ;;
        wasm) node spec/browser/module.mjs "$KANSO_RUNTIME_WASM" "$built/app.wasm" "$event" 2>&1 ;;
      esac
      echo "--"
    done < "$events")
    if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
      printf '%s\n' "$got" > "$want"
    fi
    if printf '%s\n' "$got" | diff "$want" - >/dev/null; then
      note "ok: $name answers its events ($engine)"
    else
      bad "$name answers its events ($engine)"
      printf '%s\n' "$got" | diff "$want" -
    fi
  done
  rm -rf "$built"
done

note "== the browser renders a page as the server rendered it"
# spec/runs/pages prints a page as data, then the page the server renders
# from it, then the page its templates render from the records themselves.
# Its one event is that data, and the browser module's answer to it is the
# same page, byte for byte.
server_page=$(sed -n 2p spec/runs/pages.stdout)
template_page=$(sed -n 3p spec/runs/pages.stdout)
browser_page=$(sed -n 1p spec/runs/pages.answers)
if [ "$server_page" = "$template_page" ]; then
  note "ok: pages renders from its data as from its records"
else
  bad "pages renders differently from its data"
fi
if [ "$server_page" = "$browser_page" ]; then
  note "ok: pages renders the same in the browser"
else
  bad "pages renders differently in the browser"
fi

note "== each app under spec/db says what its golden says against Postgres"
# These connect to a Postgres that trusts 127.0.0.1:54329, as CI's service
# does, and that serves TLS with spec/tls's certificate for localhost, whose
# authority they trust. SENRO_NO_DB=1 skips them and says so.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/db (SENRO_NO_DB=1)"
else
  for d in spec/db/*/; do
    name=$(basename "$d")
    want="spec/db/$name.out"
    for engine in native interp; do
      if [ "$engine" = interp ]; then
        got=$(cd "$d" && SSL_CERT_FILE="$here/spec/tls/ca.pem" "$KANSO" run . --interp 2>&1)
      else
        got=$(cd "$d" && SSL_CERT_FILE="$here/spec/tls/ca.pem" "$KANSO" run . 2>&1)
      fi
      if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
        printf '%s\n' "$got" > "$want"
      fi
      if printf '%s\n' "$got" | diff "$want" - >/dev/null; then
        note "ok: $name ($engine)"
      else
        bad "$name ($engine)"
        printf '%s\n' "$got" | diff "$want" -
      fi
    done
  done
fi

note "== each app under spec/serve answers its golden, natively and interpreted"
# Each is served and asked for /nested with curl. Its answer is another
# request to the same server, made while the first waits, so a server that
# answers one connection at a time hangs and the request times out. These
# use Postgres for their sessions, so SENRO_NO_DB=1 skips them too.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/serve (SENRO_NO_DB=1)"
else
  for d in spec/serve/*/; do
    name=$(basename "$d")
    want="spec/serve/$name.out"
    port=$(sed -n 's/^web\/serve \([0-9]*\) .*/\1/p' "$d/main.kso")
    for engine in native interp; do
      flag=""
      [ "$engine" = interp ] && flag=--interp
      log=$(mktemp)
      (cd "$d" && exec "$KANSO" run . $flag) > "$log" 2>&1 &
      server=$!
      tries=0
      while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
        sleep 0.1
        tries=$((tries + 1))
      done
      got=$(curl -s -m 10 "http://127.0.0.1:$port/nested")
      pkill -P "$server" 2>/dev/null
      kill "$server" 2>/dev/null
      wait "$server" 2>/dev/null
      if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
        printf '%s\n' "$got" > "$want"
      fi
      if printf '%s\n' "$got" | diff "$want" - >/dev/null; then
        note "ok: $name ($engine)"
      else
        bad "$name ($engine)"
        printf '%s\n' "$got" | diff "$want" -
        cat "$log"
      fi
      rm -f "$log"
    done
  done
fi

note "== the generator writes examples/notebook, which checks and serves"
# `generate new` and `generate scaffold` write an app at spec/notebook, made
# afresh each run, and refuse a resource that is there, a name or field they
# cannot read, and a parent the app does not have. What they write must be examples/notebook byte for byte: the
# two sit at the same depth, so their imports of senro read the same. The
# app must check, and served natively and interpreted it must list, make,
# show, change and remove a note, and a page under it
# (spec/generate/drive.sh). Serving uses
# Postgres, so SENRO_NO_DB=1 skips that part.
gen=spec/notebook
rm -rf "$gen"
made=$({
  "$KANSO" run generate -- new "$gen"
  "$KANSO" run generate -- scaffold "$gen" note title:text pages:int
  "$KANSO" run generate -- scaffold "$gen" page body:text note:references
  "$KANSO" run generate -- scaffold "$gen" note title:text
  "$KANSO" run generate -- scaffold "$gen" book title:words
  "$KANSO" run generate -- scaffold "$gen" book Title:text
  "$KANSO" run generate -- scaffold "$gen" book id:int
  "$KANSO" run generate -- scaffold "$gen" Book title:text
  "$KANSO" run generate -- scaffold "$gen" chapter body:text volume:references
  "$KANSO" run generate -- scaffold "$gen" book note:references page:references
} 2>&1)
if [ "${SPEC_WRITE:-}" = 1 ]; then
  printf '%s\n' "$made" > spec/generate/made.out
  rm -rf examples/notebook
  cp -R "$gen" examples/notebook
fi
if printf '%s\n' "$made" | diff spec/generate/made.out - >/dev/null; then
  note "ok: generate writes and refuses"
else
  bad "generate writes and refuses"
  printf '%s\n' "$made" | diff spec/generate/made.out -
fi
if diff -r examples/notebook "$gen" >/dev/null; then
  note "ok: what generate writes is examples/notebook"
else
  bad "what generate writes is examples/notebook"
  diff -r examples/notebook "$gen"
fi
if out=$("$KANSO" check "$gen" 2>&1); then
  note "ok: the generated app checks"
else
  bad "the generated app checks"
  echo "$out"
fi
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: serving the generated app (SENRO_NO_DB=1)"
else
  for engine in native interp; do
    flag=""
    [ "$engine" = interp ] && flag=--interp
    log=$(mktemp)
    (cd "$gen" && PGHOST=127.0.0.1 PGPORT=54329 exec "$KANSO" run . $flag) > "$log" 2>&1 &
    server=$!
    tries=0
    while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
      sleep 0.1
      tries=$((tries + 1))
    done
    got=$(sh spec/generate/drive.sh 3000 2>&1)
    pkill -P "$server" 2>/dev/null
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null
    if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
      printf '%s\n' "$got" > spec/generate/served.out
    fi
    if printf '%s\n' "$got" | diff spec/generate/served.out - >/dev/null; then
      note "ok: the generated app serves ($engine)"
    else
      bad "the generated app serves ($engine)"
      printf '%s\n' "$got" | diff spec/generate/served.out -
      cat "$log"
    fi
    rm -f "$log"
  done
fi
# A resource with many fields, written into the same app, still checks:
# every list the scaffold writes spans lines once it is too long for one.
# So does one nested under a note with a name as long as one may be.
wide="title:text author:text summary:text published_year:int page_count:int"
"$KANSO" run generate -- scaffold "$gen" book $wide isbn:text >/dev/null
"$KANSO" run generate -- scaffold "$gen" margin_footnote words:text \
  year:int note:references >/dev/null
if out=$("$KANSO" check "$gen" 2>&1); then
  note "ok: a resource with many fields checks"
else
  bad "a resource with many fields checks"
  echo "$out"
fi
rm -rf "$gen"

note "== the guestbook and the pantry, used in a browser, update in place"
# Each app is served and driven in each browser SENRO_BROWSERS names
# (chromium unless it says otherwise; CI adds firefox), through Playwright,
# which node must be able to require. Each prints what a visitor sees for
# spec/browser/<app>.out. They use Postgres, so SENRO_NO_DB=1 skips them too.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/browser (SENRO_NO_DB=1)"
else
  # Each app's page loads the app's module and the runtime built for wasm
  # (browser/build.sh): the guestbook renders its pages with it and the
  # pantry runs its planner. Both are skipped without KANSO_RUNTIME_WASM.
  apps=""
  if [ -n "${KANSO_RUNTIME_WASM:-}" ]; then
    for app in guestbook:3000 pantry:3001; do
      if KANSO=$KANSO sh browser/build.sh "examples/${app%:*}" "$KANSO_RUNTIME_WASM"; then
        apps="$apps $app"
      else
        bad "${app%:*} builds for the browser"
      fi
    done
  else
    note "SKIPPED: spec/browser (no KANSO_RUNTIME_WASM)"
  fi
  for app in $apps; do
    name=${app%:*}
    port=${app#*:}
    want=spec/browser/$name.out
    for engine in native interp; do
      flag=""
      [ "$engine" = interp ] && flag=--interp
      # A server of its own for each browser: the sign-in limit is counted
      # in the server's memory, per address, and every browser here comes
      # from one. The database carries over, so a later run finds the
      # accounts an earlier one made.
      for browser in ${SENRO_BROWSERS:-chromium}; do
        log=$(mktemp)
        # The app's mail is written to files here, where the spec reads it.
        outbox=$(mktemp -d)
        (cd "examples/$name" && SENRO_MAIL="dir:$outbox" exec "$KANSO" run . $flag) > "$log" 2>&1 &
        server=$!
        tries=0
        while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
          sleep 0.1
          tries=$((tries + 1))
        done
        got=$(node "spec/browser/$name.mjs" "$port" "$browser" "$outbox" 2>&1)
        if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
          printf '%s\n' "$got" > "$want"
        fi
        if printf '%s\n' "$got" | diff "$want" - >/dev/null; then
          note "ok: $name in $browser ($engine)"
        else
          bad "$name in $browser ($engine)"
          printf '%s\n' "$got" | diff "$want" -
          cat "$log"
        fi
        pkill -P "$server" 2>/dev/null
        kill "$server" 2>/dev/null
        wait "$server" 2>/dev/null
        rm -f "$log"
        rm -rf "$outbox"
      done
    done
  done
fi

note "== each app under spec/errors is refused as its golden says"
for d in spec/errors/*/; do
  name=$(basename "$d")
  want="spec/errors/$name.stderr"
  got=$(cd "$d" && "$KANSO" check . 2>&1)
  status=$?
  if [ "${SPEC_WRITE:-}" = 1 ]; then
    printf '%s\n' "$got" > "$want"
  fi
  if [ "$status" -eq 0 ]; then
    bad "$name compiled; it should be refused"
  elif printf '%s\n' "$got" | diff "$want" - >/dev/null; then
    note "ok: $name"
  else
    bad "$name"
    printf '%s\n' "$got" | diff "$want" -
  fi
done

cd "$here"
if [ "$fail" -ne 0 ]; then
  echo "senro specs: failures above"
  exit 1
fi
echo "senro specs: all pass"
