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
# spec/serve, served and asked over HTTP, answers its golden, and one logs the
# requests as its golden holds them; the guestbook and the pantry, used in a
# browser, update in place without a reload; the generators write
# examples/notebook, which checks and serves its resource; a lock on a
# guestbook account runs out by the clock (spec/lapsed); pages listening for
# changes cost the server a connection each and Postgres nothing
# (spec/live); each app under spec/errors is refused with the message its
# golden holds; wire and a second writing of its format read each other's
# bytes (spec/wire); and the benchmark page costs what bench/pages.golden
# pins (bench/pages.sh).
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
for d in routes models web pg kata wire spec/held spec/wire/checked data mail jobs passwords tokens clock accounts generate senro.kso examples/guestbook examples/notebook examples/pantry examples/pg spec/lapsed/later spec/live/sessions bench/pages/data.kso bench/pages/html.kso bench/pages/browser.kso; do
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

if [ "${SPEC_WRITE:-}" = 1 ]; then
  for n in 1 5 6; do
    printf '\t\t%s\n' "$(sed -n ${n}p spec/runs/pages.stdout)"
  done > spec/runs/pages.events
fi

note "== each browser module answers its events on every engine"
# An app under spec/runs with a browser.kso and a list of events in
# spec/runs/<app>.events, one to a line as the component, the action and the
# state separated by tabs, answers each as spec/runs/<app>.answers holds,
# natively, interpreted and built for the browser. The file writes a state as
# JSON, and spec/held turns it into the bytes a page holds. A page is an
# event with no component and no action, whose third field is the page's
# bytes in base64, handed over as a file. The browser build is run
# by spec/browser/module.mjs against the kanso runtime for wasm32 named by
# KANSO_RUNTIME_WASM, and is skipped without it. The JavaScript that runs it
# is the page script's own, which spec/browser/runner prints.
runner=$(mktemp)
(cd spec/browser/runner && "$KANSO" run .) > "$runner" 2>&1 || bad "the page script's module runner prints"
tab=$(printf '\t')
nl='
'
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
      component=$(printf '%s' "$line" | cut -f1)
      action=$(printf '%s' "$line" | cut -f2)
      state=$(printf '%s' "$line" | cut -f3)
      page=
      if [ -z "$component$action" ]; then
        printf '%s' "$state" | base64 -d > "$built/page"
        page="$built/page"
        held=
      else
        held=$(cd spec/held && SENRO_STATE="$state" "$KANSO" run . 2>&1)
      fi
      # Joined by hand: a command substitution would drop the newlines a page
      # event ends in.
      event="$component$nl$action$nl$held"
      case "$line" in
        *"$tab"*"$tab"*"$tab"*) event="$event$nl$(printf '%s' "$line" | cut -f4-)" ;;
      esac
      case $engine in
        native) (cd "$d" && SENRO_PAGE="$page" SENRO_EVENT="$event" "$KANSO" run browser.kso 2>&1) ;;
        interp) (cd "$d" && SENRO_PAGE="$page" SENRO_EVENT="$event" "$KANSO" run browser.kso --interp 2>&1) ;;
        wasm) node spec/browser/module.mjs "$runner" "$KANSO_RUNTIME_WASM" "$built/app.wasm" "$event" $page 2>&1 ;;
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
# spec/runs/pages prints a page as the bytes a browser is sent, then the page
# drawn by the server from the records, drawn from those bytes, and drawn by
# its templates called directly. Its first event is those bytes, and the
# browser module's answer to it is the same page, byte for byte. Its other
# two are the bytes as another compile would mark them and the bytes cut
# short, and the module draws nothing from either.
server_page=$(sed -n 2p spec/runs/pages.stdout)
bytes_page=$(sed -n 3p spec/runs/pages.stdout)
template_page=$(sed -n 4p spec/runs/pages.stdout)
browser_page=$(sed -n 1p spec/runs/pages.answers)
if [ "$server_page" = "$template_page" ] && [ "$server_page" = "$bytes_page" ]; then
  note "ok: pages renders from its bytes as from its records"
else
  bad "pages renders differently from its bytes"
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
# answers one connection at a time hangs and the request times out. Two of
# them, spec/serve/logged and spec/serve/answered, are also held to the log
# the server wrote. These
# use Postgres for their sessions, so SENRO_NO_DB=1 skips them too.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/serve (SENRO_NO_DB=1)"
else
  for d in spec/serve/*/; do
    name=$(basename "$d")
    want="spec/serve/$name.out"
    port=$(sed -n 's/^web\/serve \([0-9]*\) .*/\1/p' "$d/main.kso")
    # Below 32768, where Linux starts handing out the local ports of
    # outgoing connections. A port in that range can be held by one of this
    # run's own connections to Postgres when the app comes to listen on it.
    if [ "$port" -ge 32768 ]; then
      bad "$name listens on $port, among the ports outgoing connections take"
      continue
    fi
    for engine in native interp; do
      flag=""
      [ "$engine" = interp ] && flag=--interp
      log=$(mktemp)
      # The server may hold 256 files open, so one that keeps a connection
      # after its client has gone runs out within a spec
      # (spec/serve/hung_up).
      (cd "$d" && ulimit -n 256 && exec "$KANSO" run . $flag) > "$log" 2>&1 &
      server=$!
      tries=0
      while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
        sleep 0.1
        tries=$((tries + 1))
      done
      got=$(curl -s -m 10 "http://127.0.0.1:$port/nested")
      # What the server wrote is read before it is stopped. A request's line
      # is written before its answer, so every line is there by now, and a
      # server being ended may add a word about the signal that ended it.
      lines=$(sed 's/ in [0-9]*ms$/ in Nms/' "$log")
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
      # An app with a golden beside it for what the server wrote
      # (spec/serve/<name>.log) is held to that too: the line for each
      # request it answered, the milliseconds each took read as N.
      wrote="spec/serve/$name.log"
      if [ -f "$wrote" ]; then
        if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
          printf '%s\n' "$lines" > "$wrote"
        fi
        if printf '%s\n' "$lines" | diff "$wrote" - >/dev/null; then
          note "ok: $name's log ($engine)"
        else
          bad "$name's log ($engine)"
          printf '%s\n' "$lines" | diff "$wrote" -
        fi
      fi
      rm -f "$log"
    done
  done
fi

note "== the generator writes examples/notebook, which checks and serves"
# `generate new`, `generate scaffold` and `generate authentication` write an
# app at spec/notebook, made afresh each run, and refuse a resource that is
# there, a name or field they cannot read, a parent the app does not have,
# and authentication twice or for no app. What they write must be
# examples/notebook byte for byte, once the secret authentication made at
# random is set aside: the two sit at the same depth, so their imports of
# senro read the same. The app must check, and served natively and
# interpreted it must make an account, list, make, show, change and remove
# a note and a page under it, sign out, and reset a lost password through
# the mail it sends (spec/generate/drive.sh). Serving uses Postgres, so
# SENRO_NO_DB=1 skips that part.
# A migration's file is stamped with the moment it was written, so the
# clock is pinned here: three migrations written in one second take that
# second and the two after it.
gen=spec/notebook
rm -rf "$gen"
made=$({
  export KANSO_NOW=1794420312000
  "$KANSO" run generate -- new "$gen"
  "$KANSO" run generate -- scaffold "$gen" note title:text pages:int \
    cover:attachment
  "$KANSO" run generate -- scaffold "$gen" page body:text note:references
  "$KANSO" run generate -- authentication "$gen"
  "$KANSO" run generate -- scaffold "$gen" note title:text
  "$KANSO" run generate -- scaffold "$gen" book title:words
  "$KANSO" run generate -- scaffold "$gen" book Title:text
  "$KANSO" run generate -- scaffold "$gen" book id:int
  "$KANSO" run generate -- scaffold "$gen" book title:text:loud
  "$KANSO" run generate -- scaffold "$gen" Book title:text
  "$KANSO" run generate -- scaffold "$gen" chapter body:text volume:references
  "$KANSO" run generate -- scaffold "$gen" book note:references page:references
  "$KANSO" run generate -- authentication "$gen"
  "$KANSO" run generate -- authentication spec/nowhere
} 2>&1)
# The secret is 32 random bytes in hex, and the copy compared is given a
# fixed one.
if grep -qE '^pub secret = "[0-9a-f]{64}"$' "$gen/session.kso"; then
  note "ok: generate authentication makes a secret at random"
else
  bad "generate authentication makes a secret at random"
  grep -n "secret =" "$gen/session.kso"
fi
fixed='pub secret = "made at random by generate authentication"'
kept=$(sed "s/^pub secret = \".*\"$/$fixed/" "$gen/session.kso")
printf '%s\n' "$kept" > "$gen/session.kso"
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
# The `senro` command, as an app's author runs it: `senro new` from a
# directory outside senro, then from the app's directory a controller, a
# model, a migration of each kind its name can ask for, a mailer, a job,
# the list of generators with one the app ships, that generator, the app's
# routes, and each thing the command refuses, ending with a job asked of an
# entry that no longer finds jobs. The app must check as `new` leaves it
# and with everything written. An app imports senro by the path from
# wherever it is, so what is compared is what the command prints.
case "$KANSO" in
  */*) kanso_at=$(cd "$(dirname "$KANSO")" && pwd)/$(basename "$KANSO") ;;
  *) kanso_at=$(command -v "$KANSO") ;;
esac
senro="$PWD/bin/senro"
cmd=$(mktemp -d)
ran=$(
  cd "$cmd"
  export KANSO="$kanso_at"
  {
    "$senro" new blog
    cd blog
    "$KANSO" check . | sed 's|^.*main.kso|main.kso|'
    "$senro" generate controller pages index show create
    export KANSO_NOW=1794420312000
    "$senro" generate model tag name:text:uniq
    "$senro" generate migration create_labels name:text
    "$senro" generate migration add_color_to_tags color:text post:references
    "$senro" generate migration rename_color_to_shade_in_tags
    "$senro" generate migration remove_shade_from_tags shade
    "$senro" generate migration tidy_up
    "$senro" g migration tidy_up
    "$senro" g migration Tidy-Up
    "$senro" g migration add_weight_to_tags weight:heavy
    "$senro" g migration create_the_longest_table_anyone_ever_named a:text
    "$senro" g model tag name:text
    "$senro" g model Tag name:text
    "$senro" generate mailer account welcome password_changed
    "$senro" g mailer account welcome
    "$senro" g mailer account Welcome
    sed 's|^import ".*/mail"$|import "<senro>/mail"|' account_mailer.kso
    "$KANSO" check account_mailer.kso
    "$senro" generate job tidy
    "$senro" g job tidy
    "$senro" g job Tidy
    cat tidy_job.kso
    ls migrations | while read -r f; do
      echo "== $f"
      sed 's|^import ".*/models"$|import "<senro>/models"|' "migrations/$f"
    done
    unset KANSO_NOW
    mkdir generators
    printf 'import "std/io"\nimport "std/os"\n\n' > generators/greeting.kso
    printf 'os/args .> (a -> io/write "greeting: {a}\\n")\n' \
      >> generators/greeting.kso
    "$senro" generate
    "$senro" g greeting one two
    "$senro" routes
    "$senro" g nothing
    "$senro" g controller pages index
    "$senro" g controller things fly
    "$senro" g controller Things index
    "$senro" bogus
    "$KANSO" check . | sed 's|^.*main.kso|main.kso|'
    grep -v '^derive jobs/performers$' main.kso > main.without
    mv main.without main.kso
    "$senro" g job sweep
  } 2>&1
)
rm -rf "$cmd"
if [ "${SPEC_WRITE:-}" = 1 ]; then
  mkdir -p spec/command
  printf '%s\n' "$ran" > spec/command/ran.out
fi
if printf '%s\n' "$ran" | diff spec/command/ran.out - >/dev/null; then
  note "ok: the senro command writes, lists, runs and refuses"
else
  bad "the senro command writes, lists, runs and refuses"
  printf '%s\n' "$ran" | diff spec/command/ran.out -
fi
# What the generators write and the pantry's modules go through their
# models: none of them names the pg module (kanso#2394).
sql=$(grep -n "pg/" "$gen/note.kso" "$gen/notes.kso" "$gen/page.kso" \
  "$gen/pages.kso" "$gen/user.kso" "$gen/registration.kso" \
  "$gen/session.kso" "$gen/resets.kso" examples/pantry/items.kso \
  examples/pantry/stock.kso)
# The guestbook's modules hold no query either; its entry opens and closes
# the database and does nothing else with it.
asked=$(grep -n "pg/query\|pg/run\|pg/exec" examples/guestbook/*.kso \
  examples/guestbook/removal/*.kso)
sql="$sql$asked"
if [ -z "$sql" ]; then
  note "ok: the generators, the pantry and the guestbook write no SQL"
else
  bad "the generators, the pantry and the guestbook write no SQL"
  echo "$sql"
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
    outbox=$(mktemp -d)
    (cd "$gen" && PGHOST=127.0.0.1 PGPORT=54329 SENRO_MAIL="dir:$outbox" \
      exec "$KANSO" run . $flag) > "$log" 2>&1 &
    server=$!
    tries=0
    while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
      sleep 0.1
      tries=$((tries + 1))
    done
    got=$(sh spec/generate/drive.sh 3000 "$outbox" 2>&1)
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
    rm -rf "$outbox"
  done
fi
# A resource with many fields, written into the same app, still checks:
# every list the scaffold writes spans lines once it is too long for one.
# So does one nested under a note with a name as long as one may be.
wide="title:text author:text summary:text published_year:int page_count:int"
"$KANSO" run generate -- scaffold "$gen" book $wide isbn:text >/dev/null
"$KANSO" run generate -- scaffold "$gen" margin_footnote words:text \
  year:int scan:attachment note:references >/dev/null
if out=$("$KANSO" check "$gen" 2>&1); then
  note "ok: a resource with many fields checks"
else
  bad "a resource with many fields checks"
  echo "$out"
fi
rm -rf "$gen"

note "== pages listening for changes cost a connection each, and none once gone"
# spec/live/app is served with a heartbeat of 300 ms and twenty pages hold
# its stream at /senro/live open (spec/live/drive.sh). The server has one
# more file open for each and Postgres no more sessions; a change reaches
# every page; and once the pages have gone the server is back where it
# began without anyone writing. The files are counted under /proc, so the
# spec is skipped where there is none, and it uses Postgres, so
# SENRO_NO_DB=1 skips it too.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/live (SENRO_NO_DB=1)"
elif [ ! -d /proc/self/fd ]; then
  note "SKIPPED: spec/live (no /proc to count open files in)"
else
  for engine in native interp; do
    flag=""
    [ "$engine" = interp ] && flag=--interp
    log=$(mktemp)
    (cd spec/live/app && SENRO_LIVE_BEAT=300 exec "$KANSO" run . $flag) > "$log" 2>&1 &
    server=$!
    tries=0
    while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
      sleep 0.1
      tries=$((tries + 1))
    done
    # Natively `kanso run` starts the program it built, and the server is
    # that child; interpreted, the server is kanso itself.
    pid=$(pgrep -P "$server" | head -1)
    [ -z "$pid" ] && pid=$server
    got=$(KANSO=$KANSO sh spec/live/drive.sh 24420 "$pid" 2>&1)
    pkill -P "$server" 2>/dev/null
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null
    if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
      printf '%s\n' "$got" > spec/live/served.out
    fi
    if printf '%s\n' "$got" | diff spec/live/served.out - >/dev/null; then
      note "ok: pages listening ($engine)"
    else
      bad "pages listening ($engine)"
      printf '%s\n' "$got" | diff spec/live/served.out -
      cat "$log"
    fi
    rm -f "$log"
  done
fi

note "== a lock on a guestbook account runs out by the clock"
# The guestbook is served and used over HTTP (spec/lapsed/drive.sh): three
# wrong passwords lock an account, and an hour and a minute later a wrong
# password starts a new run of three and the right one signs in. A server
# of its own, since the sign-in limit is counted in the server's memory. It
# uses Postgres, so SENRO_NO_DB=1 skips it.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/lapsed (SENRO_NO_DB=1)"
else
  for engine in native interp; do
    flag=""
    [ "$engine" = interp ] && flag=--interp
    log=$(mktemp)
    outbox=$(mktemp -d)
    (cd examples/guestbook && SENRO_MAIL="dir:$outbox" exec "$KANSO" run . $flag) > "$log" 2>&1 &
    server=$!
    tries=0
    while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
      sleep 0.1
      tries=$((tries + 1))
    done
    got=$(KANSO=$KANSO sh spec/lapsed/drive.sh 3000 "$outbox" 2>&1)
    pkill -P "$server" 2>/dev/null
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null
    if [ "${SPEC_WRITE:-}" = 1 ] && [ "$engine" = native ]; then
      printf '%s\n' "$got" > spec/lapsed/served.out
    fi
    if printf '%s\n' "$got" | diff spec/lapsed/served.out - >/dev/null; then
      note "ok: a lock runs out ($engine)"
    else
      bad "a lock runs out ($engine)"
      printf '%s\n' "$got" | diff spec/lapsed/served.out -
      cat "$log"
    fi
    rm -f "$log"
    rm -rf "$outbox"
  done
fi

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
          # What a failure cannot say for itself (kanso#2397): whether the
          # server still answers, and which kanso processes are alive, an
          # earlier spec's among them.
          echo "--- the server, asked for / after the failure"
          curl -sS -m 10 -o /dev/null \
            -w "GET /: %{http_code} in %{time_total}s\n" \
            "http://127.0.0.1:$port/" || echo "no answer in 10s"
          echo "--- kanso processes"
          ps -eo pid,ppid,stat,etime,args \
            | grep "[k]anso run\|[k]anso_run_" | cut -c1-160
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
# wire/wire.kso and a second writing of its format in JavaScript
# (spec/wire/reference.mjs) each read what the other wrote for twenty
# thousand random values: every length a string's count turns over at, code
# points from each length utf-8 has, integers at the ends of 64 bits, floats,
# and lists and maps of those. spec/wire/fuzz.mjs runs longer when asked.
note "== wire agrees with its reference"
if command -v node > /dev/null 2>&1; then
  if node spec/wire/fuzz.mjs "$KANSO" 20000 > /dev/null 2>&1; then
    note "ok: wire reads what its reference writes, and is read by it"
  else
    bad "wire and its reference disagree"
    node spec/wire/fuzz.mjs "$KANSO" 20000 2>&1 | grep -v '^ *[0-9]' | head -6
  fi
else
  note "SKIPPED: wire against its reference (no node)"
fi

# The benchmark's rows are counted in wasm, so it wants the runtime built for
# wasm32 and kanso's count_module, and is skipped without them.
note "== the benchmark page costs what its golden pins"
if [ -z "${KANSO_RUNTIME_WASM:-}" ] || [ -z "${KANSO_COUNT:-}" ]; then
  note "SKIPPED: bench/pages (no KANSO_RUNTIME_WASM or no KANSO_COUNT)"
elif [ "${SPEC_WRITE:-}" = 1 ]; then
  KANSO="$KANSO" sh bench/pages.sh --write || bad "bench/pages"
elif KANSO="$KANSO" sh bench/pages.sh; then
  note "ok: bench/pages"
else
  bad "bench/pages"
fi

if [ "$fail" -ne 0 ]; then
  echo "senro specs: failures above"
  exit 1
fi
echo "senro specs: all pass"
