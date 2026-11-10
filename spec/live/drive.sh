# Counts what pages listening at /senro/live cost a served app, and what is
# left when they go. Twenty pages open a stream each and hold it. The
# server should have one more file open for each and Postgres no more
# sessions than before, since one session listens for them all. A request
# that may have changed something reaches every page. Then the pages go,
# and with nobody writing the server should be back where it started
# within two beats of its heartbeat, which the spec sets to 300 ms. Run
# from senro's directory with the server's process id:
#
#   sh spec/live/drive.sh <port> <pid>
at="http://127.0.0.1:$1"
pid=$2
heard=$(mktemp -d)
files() { ls "/proc/$pid/fd" | wc -l; }
sessions() { "$KANSO" run spec/live/sessions; }
more() { echo "$(($(files) - files0)) more files, $(($(sessions) - sessions0)) more sessions"; }

sleep 0.5
files0=$(files)
sessions0=$(sessions)
pages=""
n=1
while [ $n -le 20 ]; do
  curl -sN -m 30 "$at/senro/live" > "$heard/$n" 2>/dev/null &
  pages="$pages $!"
  n=$((n + 1))
done
sleep 1
echo "20 pages listening: $(more)"
curl -s -o /dev/null -d "_method=PATCH" "$at/notes/7"
sleep 1
echo "a change reaches $(grep -l "^data: changed" "$heard"/* | wc -l | tr -d ' ') of them"
kill $pages 2>/dev/null
wait $pages 2>/dev/null
sleep 2
echo "after they left, with nobody writing: $(more)"
rm -rf "$heard"
