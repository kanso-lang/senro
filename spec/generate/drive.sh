# Uses an app `generate` made, over HTTP, as a visitor would: lists the
# notes, gives a page count that is no number, makes one, shows it, opens its
# form, changes it, removes it, and asks for it again. Then the pages nested
# under a note: makes one, asks for it under another note and under one that
# is not there, changes it, and removes its note, which removes it. Prints
# each answer's status and where it sends the browser, or the page's text
# with its tags taken out. Postgres numbers a row by what was made before,
# so an id reads as N. Run as:
#
#   sh spec/generate/drive.sh <port>
at="http://127.0.0.1:$1"
ids() {
  sed 's|/notes/[0-9][0-9]*|/notes/N|g; s/Note [0-9][0-9]*/Note N/g' |
    sed 's|/pages/[0-9][0-9]*|/pages/N|g; s/Page [0-9][0-9]*/Page N/g'
}
page() { curl -s "$at$1" | sed 's/<[^>]*>/ /g' | tr -s ' \n' ' ' | ids; echo; }
sent() { curl -s -o /dev/null -w "%{http_code} to %{redirect_url}\n" -d "$2" "$at$1" | sed "s|$at||" | ids; }
echo "the list: $(page /notes)"
refused=$(curl -s -w "\n%{http_code}" -d "title=First&pages=twelve" "$at/notes")
echo "pages of twelve: $(echo "$refused" | tail -1) $(echo "$refused" | grep -o 'Give a whole number.')"
made=$(curl -s -o /dev/null -w "%{redirect_url}" -d "title=First&pages=12" "$at/notes" | sed "s|$at||")
echo "making one: sent to $(echo "$made" | ids)"
echo "it shows: $(page "$made")"
echo "its form: $(curl -s "$at$made/edit" | grep -o 'value="[^"]*"' | tr '\n' ' ')"
echo "changing it: $(sent "$made" "_method=PATCH&title=Renamed&pages=13")"
echo "the list then: $(page /notes)"
echo "removing it: $(sent "$made" "_method=DELETE")"
echo "asked for again: $(curl -s -o /dev/null -w "%{http_code}" "$at$made")"

# A note with a page, and another note.
asked() { curl -s -o /dev/null -w "%{http_code} %{redirect_url}" "$@" | sed "s|$at||" | ids; echo; }
held=$(curl -s -o /dev/null -w "%{redirect_url}" -d "title=Held&pages=1" "$at/notes" | sed "s|$at||")
other=$(curl -s -o /dev/null -w "%{redirect_url}" -d "title=Other&pages=2" "$at/notes" | sed "s|$at||")
echo "its pages: $(page "$held/pages")"
kept=$(curl -s -o /dev/null -w "%{redirect_url}" -d "body=hello" "$at$held/pages" | sed "s|$at||")
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
curl -s -o /dev/null -d "_method=DELETE" "$at$other"
