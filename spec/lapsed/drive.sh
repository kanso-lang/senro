# Uses the guestbook over HTTP to watch a lock run out. An account is made
# and its address confirmed through the mail the app writes to <outbox>.
# Three wrong passwords lock it, and the right one is then told so. An hour
# and a minute later (spec/lapsed/later moves the lock that far back, which
# is the same thing to an app that reads the clock at each sign-in) a wrong
# password is the first of a new run: it and two more lock the account
# again, and mail a second link. Another hour on, the right password signs
# in. Prints each answer's status. Each run makes an account of its own,
# never printed, and tries to sign in nine times, under the ten the
# guestbook allows one address in three minutes. Run from senro's directory:
#
#   sh spec/lapsed/drive.sh <port> <outbox>
at="http://127.0.0.1:$1"
outbox=$2
name="gil$(date +%s%N)"
email="$name@guestbook.test"
right="gils password"
tried() {
  curl -s -o /dev/null -w "%{http_code}" -d "name=$name" \
    --data-urlencode "password=$1" "$at/session"
}
# The mails to this account with <subject>, once there are <count> of them:
# the guestbook queues its mail and a worker sends it a moment later.
mailed() {
  tries=0
  found=0
  while [ "$found" -lt "$2" ] && [ $tries -lt 300 ]; do
    found=$(grep -l "^To: $email" "$outbox"/* 2>/dev/null |
      xargs -r grep -l "^Subject: $1" | wc -l)
    [ "$found" -lt "$2" ] && sleep 0.1
    tries=$((tries + 1))
  done
  grep -l "^To: $email" "$outbox"/* 2>/dev/null | xargs -r grep -l "^Subject: $1"
}
later() { "$KANSO" run spec/lapsed/later -- "$name"; }

made=$(curl -s -o /dev/null -w "%{http_code}" -d "name=$name&email=$email" \
  --data-urlencode "password=$right" "$at/registration")
echo "making an account: $made"
link=$(grep -o "http://[^ ]*/edit" $(mailed "Confirm" 1) | tr -d '\r')
confirmed=$(curl -s -o /dev/null -w "%{http_code}" -d "_method=PATCH" "${link%/edit}")
echo "confirming its address: $confirmed"
echo "three wrong passwords: $(tried one) $(tried two) $(tried three)"
echo "the right one, while it is locked: $(tried "$right")"
later
echo "an hour and a minute on, a wrong one: $(tried four)"
echo "two more: $(tried five) $(tried six)"
echo "the right one, locked again: $(tried "$right")"
echo "mails to unlock it: $(mailed "Unlock" 2 | wc -l | tr -d ' ')"
later
echo "another hour on, the right one: $(tried "$right")"
