# Uses an app `generate` made, over HTTP, as a visitor would: lists the
# notes, gives a page count that is no number, makes one, shows it, opens its
# form, changes it, removes it, and asks for it again. Prints each answer's status and where it sends the
# browser, or the page's text with its tags taken out. Postgres numbers a
# note by what was made before, so an id reads as N. Run as:
#
#   sh spec/generate/drive.sh <port>
at="http://127.0.0.1:$1"
ids() { sed 's|/notes/[0-9][0-9]*|/notes/N|g; s/Note [0-9][0-9]*/Note N/g'; }
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
