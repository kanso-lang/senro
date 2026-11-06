#!/bin/sh
# Runs the guestbook in one browser on one engine again and again, each time
# against a server of its own, as spec.sh runs it once. For kanso#2363: the
# sign-out step timed out once in Firefox on the interpreter.
#
#   KANSO=... KANSO_RUNTIME_WASM=... sh spec/browser/loop.sh <browser> <engine> <times>
set -u
KANSO=${KANSO:-kanso}
export SENRO_PASSWORD_ROUNDS=30
browser=$1
engine=$2
times=$3
flag=""
[ "$engine" = interp ] && flag=--interp
KANSO=$KANSO sh browser/build.sh examples/guestbook "$KANSO_RUNTIME_WASM" || exit 1
failed=0
i=1
while [ "$i" -le "$times" ]; do
  log=$(mktemp)
  outbox=$(mktemp -d)
  (cd examples/guestbook && SENRO_MAIL="dir:$outbox" exec "$KANSO" run . $flag) > "$log" 2>&1 &
  server=$!
  tries=0
  while ! grep -q "senro on port" "$log" && [ $tries -lt 600 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  start=$(date +%s)
  got=$(node spec/browser/guestbook.mjs 3000 "$browser" "$outbox" 2>&1)
  took=$(( $(date +%s) - start ))
  if printf '%s\n' "$got" | diff spec/browser/guestbook.out - >/dev/null; then
    echo "run $i: ok in ${took}s"
  else
    echo "run $i: FAILED in ${took}s"
    printf '%s\n' "$got" | diff spec/browser/guestbook.out -
    echo "--- server log"
    cat "$log"
    failed=$((failed + 1))
  fi
  pkill -P "$server" 2>/dev/null
  kill "$server" 2>/dev/null
  wait "$server" 2>/dev/null
  rm -f "$log"
  rm -rf "$outbox"
  i=$((i + 1))
done
echo "$browser ($engine): $failed of $times failed"
[ "$failed" -eq 0 ]
