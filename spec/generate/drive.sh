# Uses an app `generate` made, over HTTP, as a visitor would. A visitor who
# has not signed in is sent to sign in; one makes an account, which signs
# them in. Then the notes: lists them, gives a page count that is no number,
# makes one, shows it, opens its form, changes it, removes it, and asks for
# it again. Then the pages nested under a note: makes one, asks for it under
# another note and under one that is not there, changes it, and removes its
# note, which removes it. Last, signing out, a wrong password, and a lost
# one: a link is mailed to <outbox>, followed, and the new password signs
# in. Prints each answer's status and where it sends the browser, or the
# page's text with its tags taken out. Postgres numbers a row by what was
# made before, so an id reads as N, and each run makes an account of its
# own, never printed. Run as:
#
#   sh spec/generate/drive.sh <port> <outbox>
at="http://127.0.0.1:$1"
outbox=$2
jar=$(mktemp)
email="drive-$(date +%s%N)@notebook.test"
ids() {
  sed 's|/notes/[0-9][0-9]*|/notes/N|g; s/Note [0-9][0-9]*/Note N/g' |
    sed 's|/pages/[0-9][0-9]*|/pages/N|g; s/Page [0-9][0-9]*/Page N/g'
}
c() { curl -s -b "$jar" -c "$jar" "$@"; }
page() { c "$at$1" | sed 's/<[^>]*>/ /g' | tr -s ' \n' ' ' | ids; echo; }
sent() { c -o /dev/null -w "%{http_code} to %{redirect_url}\n" -d "$2" "$at$1" | sed "s|$at||" | ids; }
echo "not signed in: $(curl -s -o /dev/null -w "%{http_code} to %{redirect_url}" "$at/notes" | sed "s|$at||")"
echo "a short password: $(c -o /dev/null -w "%{http_code}" -d "email=$email&password=short" "$at/registration")"
echo "making an account: $(sent /registration "email=$email&password=first-password")"
echo "the same address again: $(curl -s -d "email=$email&password=first-password" "$at/registration" | grep -o 'That address has an account.')"
echo "the list: $(page /notes)"
refused=$(c -w "\n%{http_code}" -d "title=First&pages=twelve" "$at/notes")
echo "pages of twelve: $(echo "$refused" | tail -1) $(echo "$refused" | grep -o 'Give a whole number.')"
made=$(c -o /dev/null -w "%{redirect_url}" -d "title=First&pages=12" "$at/notes" | sed "s|$at||")
echo "making one: sent to $(echo "$made" | ids)"
echo "it shows: $(page "$made")"
echo "its form: $(c "$at$made/edit" | grep -o 'value="[^"]*"' | tr '\n' ' ')"
echo "changing it: $(sent "$made" "_method=PATCH&title=Renamed&pages=13")"
echo "the list then: $(page /notes)"
echo "removing it: $(sent "$made" "_method=DELETE")"
echo "asked for again: $(c -o /dev/null -w "%{http_code}" "$at$made")"

# A note with a page, and another note.
asked() { c -o /dev/null -w "%{http_code} %{redirect_url}" "$@" | sed "s|$at||" | ids; echo; }
held=$(c -o /dev/null -w "%{redirect_url}" -d "title=Held&pages=1" "$at/notes" | sed "s|$at||")
other=$(c -o /dev/null -w "%{redirect_url}" -d "title=Other&pages=2" "$at/notes" | sed "s|$at||")
echo "its pages: $(page "$held/pages")"
kept=$(c -o /dev/null -w "%{redirect_url}" -d "body=hello" "$at$held/pages" | sed "s|$at||")
echo "making a page: sent to $(echo "$kept" | ids)"
echo "the page: $(page "$kept")"
under="$other/pages/${kept##*/}"
echo "under another note: $(asked "$at$under")"
echo "changed there: $(asked -d "_method=PATCH&body=moved" "$at$under")"
echo "removed there: $(asked -d "_method=DELETE" "$at$under")"
echo "under no note: $(asked "$at/notes/0/pages") $(asked -d body=x "$at/notes/0/pages")"
echo "changing it: $(asked -d "_method=PATCH&body=changed" "$at$kept")"
echo "the pages then: $(page "$held/pages")"
echo "removing its note: $(asked -d "_method=DELETE" "$at$held")"
echo "the page then: $(asked "$at$kept")"
c -o /dev/null -d "_method=DELETE" "$at$other"

# Signing out, signing in with a wrong password, and a lost one.
echo "signing out: $(sent /session "_method=DELETE")"
echo "the notes then: $(asked "$at/notes")"
echo "a wrong password: $(c -o /dev/null -w "%{http_code}" -d "email=$email&password=wrong" "$at/session")"
echo "asking for a link: $(sent /resets "email=$email")"
mail=""
tries=0
while [ -z "$mail" ] && [ $tries -lt 300 ]; do
  mail=$(grep -l "^To: $email" "$outbox"/* 2>/dev/null | head -1)
  [ -z "$mail" ] && sleep 0.1
  tries=$((tries + 1))
done
link=$(grep -o "http://[^ ]*/edit" "$mail" | tr -d '\r' | sed "s|$at||")
echo "its form: $(asked "$at$link")"
echo "choosing a new one: $(asked -d "_method=PATCH&password=second-password" "$at${link%/edit}")"
echo "the link again: $(asked "$at$link")"
echo "the old password: $(c -o /dev/null -w "%{http_code}" -d "email=$email&password=first-password" "$at/session")"
echo "the new one: $(sent /session "email=$email&password=second-password")"
rm -f "$jar"
