#!/bin/sh
# senro's specs, run against the kanso the repo pins (.kanso-version):
#
#   KANSO=/path/to/kanso sh spec.sh
#
# Every module and example checks clean; the guestbook derives the schema and
# route table its golden holds; kata compiles each view to the file beside it;
# and each app under spec/errors is refused with the message its golden holds.
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
