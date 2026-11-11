# Uses an app `generate` made, over HTTP, as a visitor would. A visitor who
# has not signed in is sent to sign in; one makes an account, which signs
# them in. Then the notes: lists them, gives a page count that is no number,
# makes one, shows it as a page and as JSON, opens its form, changes it,
# asks for the list as JSON and for its second page, which is empty and
# links back to the first, removes it, and asks for it again. Then a note
# with a cover: the file is sent as a browser sends it, comes back as it was
# sent, and stays when the note is changed without choosing another. Then
# the pages nested under a note: makes one, asks for it under another note
# and under one that is not there, changes it, and removes its note, which
# removes it. Then the readings, a resource with no pages: one is made
# with JSON and one with a form, a field that breaks its rule is answered
# with the problem, one is read, changed in part and listed, and both are
# removed. Then signing out, a wrong password, and a lost one: a link is
# mailed to <outbox>, followed, and the new password signs in. Last, runs
# of wrong passwords: four leave the account open, and five in a row lock
# it, after which the right password is told so. Prints each
# answer's status and where it sends the browser, or the page's text with
# its tags taken out. Postgres numbers a row by what was made before, so an
# id reads as N, as a time in JSON reads as T, and each run makes an account
# of its own, never printed. Run as:
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
jsonned() { sed -E 's/"(id|note_id)":[0-9]+/"\1":N/g; s/"(created|updated)_at":"[^"]*"/"\1_at":"T"/g'; }
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
echo "it as json: $(c "$at$made.json" | jsonned)"
echo "its form: $(c "$at$made/edit" | grep -o 'value="[^"]*"' | tr '\n' ' ')"
echo "changing it: $(sent "$made" "_method=PATCH&title=Renamed&pages=13")"
echo "the list then: $(page /notes)"
echo "the list as json: $(c -H "Accept: application/json" "$at/notes" | jsonned)"
echo "its second page: $(page "/notes?page=2")"
echo "removing it: $(sent "$made" "_method=DELETE")"
echo "asked for again: $(c -o /dev/null -w "%{http_code}" "$at$made")"

# A note with a cover. The cover's key is random, so it is not printed.
png=$(mktemp)
got=$(mktemp)
printf '\211PNG\r\n\032\n\000\377 a cover' > "$png"
covered=$(c -o /dev/null -w "%{redirect_url}" -F title=Covered -F pages=3 \
  -F "cover=@$png;type=image/png" "$at/notes" | sed "s|$at||")
echo "a note with a cover: $(page "$covered")"
cover=$(c "$at$covered" | grep -o '/senro/blobs/[0-9a-f]*')
fetched=$(c -o "$got" -w "%{http_code} %{content_type}" "$at$cover")
same=$(cmp -s "$png" "$got" && echo "as sent" || echo "changed")
echo "its cover: $fetched, $same"
echo "its form: $(c "$at$covered/edit" | grep -o 'Leave it empty[^<]*')"
changed=$(c -o /dev/null -w "%{http_code}" -F _method=PATCH -F title=Recovered \
  -F pages=4 -F cover= "$at$covered")
echo "changed without a file: $changed"
again=$(c "$at$covered" | grep -o '/senro/blobs/[0-9a-f]*')
echo "its cover then: $([ "$again" = "$cover" ] && echo "the same" || echo "$again")"
c -o /dev/null -d "_method=DELETE" "$at$covered"
rm -f "$png" "$got"

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

# The readings, which `generate resource` wrote: an API with no pages.
# An id reads as N and a time as T, as above.
j() { c -H "Content-Type: application/json" "$@"; }
api() {
  tr -d '\n' | sed -E 's/"id":[0-9]+/"id":N/g' |
    sed -E 's/"(created|updated)_at":"[^"]*"/"\1_at":"T"/g'
  echo
}
id_of() { grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
first=$(j -w " %{http_code}" -d '{"title":"Dune","minutes":45}' "$at/readings")
second=$(c -w " %{http_code}" -d "title=Emma&minutes=30" "$at/readings")
echo "a reading made with json: $(echo "$first" | api)"
echo "one made with a form: $(echo "$second" | api)"
long='{"title":"Ulysses","minutes":"many"}'
echo "minutes that are no number: $(j -w " %{http_code}" -d "$long" "$at/readings" | api)"
one="$at/readings/$(echo "$first" | id_of)"
other="$at/readings/$(echo "$second" | id_of)"
echo "it is read: $(c "$one" | api)"
echo "changed in part: $(j -X PATCH -d '{"minutes":50}' "$one" | api)"
echo "changed by nothing: $(j -X PATCH -d '{"pages":9}' "$one" | api)"
echo "the readings: $(c "$at/readings" | api)"
echo "removed: $(c -o /dev/null -w "%{http_code}" -X DELETE "$one")"
echo "read again: $(c -o /dev/null -w "%{http_code}" "$one")"
c -o /dev/null -X DELETE "$other"

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

# Runs of wrong passwords. The sign-in above ended the run before it, so
# four more leave the account open. Five in a row lock it: the right
# password is then told so, and a wrong one is answered as ever. One
# address may try ten times in three minutes, so each run here comes from
# an address of its own.
tried() { c --interface "$1" -o /dev/null -w "%{http_code}" -d "email=$email&password=$2" "$at/session"; }
wrongs() {
  n=0
  while [ $n -lt "$2" ]; do
    printf ' %s' "$(tried "$1" wrong)"
    n=$((n + 1))
  done
}
c -o /dev/null -d "_method=DELETE" "$at/session"
echo "four wrong passwords:$(wrongs 127.0.0.2 4)"
echo "the right one then: $(tried 127.0.0.2 second-password)"
c -o /dev/null -d "_method=DELETE" "$at/session"
echo "five wrong passwords:$(wrongs 127.0.0.3 5)"
shut=$(c --interface 127.0.0.3 -w "\n%{http_code}" -d "email=$email&password=second-password" "$at/session")
echo "the right one then: $(echo "$shut" | tail -1) $(echo "$shut" | grep -o 'This account is locked[^<]*')"
echo "a wrong one then: $(tried 127.0.0.3 wrong)"
rm -f "$jar"
