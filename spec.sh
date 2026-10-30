#!/bin/sh
# senro's specs, run against the kanso the repo pins (.kanso-version):
#
#   KANSO=/path/to/kanso sh spec.sh
#
# Every module and example checks clean; the guestbook derives the schema and
# route table its golden holds; kata compiles each view to the file beside it;
# each app under spec/runs prints its golden on both engines; each app under
# spec/db, run against a live Postgres, prints its golden on both engines; and
# each app under spec/errors is refused with the message its golden holds.
# Set SPEC_WRITE=1 to rewrite the goldens from what this kanso says.
set -u
KANSO=${KANSO:-kanso}
fail=0
here=$(pwd)

note() { echo "$1"; }
bad() { echo "FAIL: $1"; fail=1; }

note "== every module and example checks"
for d in routes models web pg kata examples/guestbook examples/pg bin/kata; do
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

note "== kata writes each view the guestbook holds"
for slim in examples/guestbook/views/*.slim; do
  kso=${slim%.slim}.kso
  got=$("$KANSO" run bin/kata -- "$slim" 2>&1)
  if printf '%s\n' "$got" | diff "$kso" - >/dev/null; then
    note "ok: $kso"
  else
    bad "$kso is not what kata writes from $slim"
    printf '%s\n' "$got" | diff "$kso" -
  fi
done

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
