#!/bin/sh
# senro's specs, run against the kanso the repo pins (.kanso-version):
#
#   KANSO=/path/to/kanso sh spec.sh
#
# Every module and example checks clean; the guestbook derives the schema,
# route table and views its golden holds; each app under spec/runs prints its
# golden on both engines; each app under spec/db, run against a live Postgres,
# prints its golden on both engines; each app under spec/serve, served and
# asked over HTTP, answers its golden; the guestbook and the pantry, used in
# a browser, update in place without a reload; and each app under spec/errors
# is refused with the message its golden holds.
# Set SPEC_WRITE=1 to rewrite the goldens from what this kanso says.
set -u
KANSO=${KANSO:-kanso}
fail=0
here=$(pwd)

note() { echo "$1"; }
bad() { echo "FAIL: $1"; fail=1; }

note "== every module and example checks"
for d in routes models web pg kata examples/guestbook examples/pantry examples/pg; do
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

note "== the guestbook and the pantry, used in a browser, update in place"
# Each app is served and driven in each browser SENRO_BROWSERS names
# (chromium unless it says otherwise; CI adds firefox), through Playwright,
# which node must be able to require. Each prints what a visitor sees for
# spec/browser/<app>.out. They use Postgres, so SENRO_NO_DB=1 skips them too.
if [ "${SENRO_NO_DB:-}" = 1 ]; then
  note "SKIPPED: spec/browser (SENRO_NO_DB=1)"
else
  for app in guestbook:3000 pantry:3001; do
    name=${app%:*}
    port=${app#*:}
    want=spec/browser/$name.out
    for engine in native interp; do
      flag=""
      [ "$engine" = interp ] && flag=--interp
      log=$(mktemp)
      (cd "examples/$name" && exec "$KANSO" run . $flag) > "$log" 2>&1 &
      server=$!
      tries=0
      while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
        sleep 0.1
        tries=$((tries + 1))
      done
      for browser in ${SENRO_BROWSERS:-chromium}; do
        got=$(node "spec/browser/$name.mjs" "$port" "$browser" 2>&1)
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
      done
      pkill -P "$server" 2>/dev/null
      kill "$server" 2>/dev/null
      wait "$server" 2>/dev/null
      rm -f "$log"
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
